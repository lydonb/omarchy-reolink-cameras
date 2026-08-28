pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "lib/EventNormalizer.js" as Events
import "lib/Time.js" as Time

Panel {
  id: root

  moduleName: "io.github.rodrix2000.reolink-cameras"
  ipcTarget: moduleName
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property var previewService: null
  property string view: "overview"
  property bool showAddForm: false
  property bool sirenConfirmation: false
  property bool removeConfirmation: false
  property bool forgetAllConfirmation: false
  property string removeHostId: ""
  property bool sirenActive: false
  property bool spotlightOn: false

  readonly property var barIdentity: hostWidget || root
  readonly property var effectiveService: service
  readonly property var cameras: effectiveService && effectiveService.cameras ? effectiveService.cameras : []
  readonly property var selectedCamera: effectiveService ? effectiveService.selectedCamera : null
  readonly property var selectedHost: selectedCamera && effectiveService
    ? effectiveService.hostForId(selectedCamera.hostId) : null
  readonly property bool formEditing: addressField.activeFocus || usernameField.activeFocus
    || passwordField.activeFocus || displayNameField.activeFocus || portField.activeFocus
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function registerPreview() {
    if (!opened || !effectiveService || previewService === effectiveService) return
    if (previewService) previewService.setPanelOpen(false)
    previewService = effectiveService
    previewService.setPanelOpen(true)
  }

  function unregisterPreview() {
    if (!previewService) return
    previewService.setPanelOpen(false)
    previewService = null
  }

  function open() {
    root.controller.show()
    registerPreview()
  }

  function close() {
    if (effectiveService) {
      effectiveService.stopAllPtz()
    }
    unregisterPreview()
    sirenConfirmation = false
    removeConfirmation = false
    forgetAllConfirmation = false
    root.controller.hide()
  }

  Component.onDestruction: {
    if (effectiveService) {
      effectiveService.stopAllPtz()
    }
    unregisterPreview()
  }

  onEffectiveServiceChanged: {
    if (previewService && previewService !== effectiveService) unregisterPreview()
    if (opened) registerPreview()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function submitAdd() {
    if (!effectiveService) return
    var passwordValue = passwordField.text
    passwordField.text = ""
    effectiveService.addHost({
      address: addressField.text,
      port: Number(portField.text),
      rtspPort: 554,
      transport: transportDropdown.value,
      tlsMode: tlsDropdown.value,
      username: usernameField.text,
      displayName: displayNameField.text
    }, passwordValue)
    passwordValue = ""
  }

  function tabButtonWidth() {
    return Math.floor((panel.contentWidth - Style.space(18)) / 4)
  }

  Connections {
    target: root.effectiveService
    function onAddCompleted(ok, message) {
      if (ok) {
        root.showAddForm = false
        root.view = "overview"
        addressField.text = ""
        displayNameField.text = ""
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(720))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.formEditing || root.sirenConfirmation
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: contentColumn
          width: scroll.width
          spacing: Style.space(12)

          Row {
            width: parent.width
            spacing: Style.space(10)

            Column {
              width: parent.width - addButton.width - parent.spacing
              spacing: Style.space(3)

              Text {
                text: "REOLINK CAMERAS"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                font.letterSpacing: 1
              }

              Text {
                text: !root.effectiveService || !root.effectiveService.configReady ? "Starting securely…"
                  : root.cameras.length === 0 ? "No cameras configured"
                  : root.effectiveService.onlineCount + " of " + root.cameras.length + " online"
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Button {
              id: addButton
              text: root.showAddForm ? "Done" : "+ Add"
              foreground: root.foreground
              bordered: true
              focusable: true
              onClicked: root.showAddForm = !root.showAddForm
            }
          }

          Text {
            visible: root.effectiveService && root.effectiveService.lastError !== ""
            width: parent.width
            text: root.effectiveService ? root.effectiveService.lastError : ""
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.effectiveService && root.effectiveService.notice !== ""
            width: parent.width
            text: root.effectiveService ? root.effectiveService.notice : ""
            color: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Button {
            visible: root.effectiveService && root.effectiveService.cleanupHostIds.length > 0
            enabled: root.effectiveService && !root.effectiveService.addInProgress
            width: parent.width
            text: "Retry credential cleanup"
            foreground: Color.urgent
            bordered: true
            onClicked: if (root.effectiveService) root.effectiveService.retryCredentialCleanup()
          }

          BorderSurface {
            visible: root.showAddForm || root.cameras.length === 0
            width: parent.width
            height: addForm.implicitHeight + Style.space(28)
            color: Util.alpha(root.foreground, 0.035)
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            radius: Style.cornerRadius

            Column {
              id: addForm
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(14)
              spacing: Style.space(9)

              PanelSectionHeader { text: "ADD CAMERA OR RECORDER"; foreground: root.foreground; fontFamily: root.fontFamily }

              TextField {
                id: addressField
                width: parent.width
                placeholderText: "Host or IP · 192.168.20.10"
                foreground: root.foreground
              }

              Row {
                width: parent.width
                spacing: Style.space(8)
                Dropdown {
                  id: transportDropdown
                  width: (parent.width - parent.spacing) * 0.55
                  showLabel: false
                  value: "https"
                  options: [{ value: "https", label: "HTTPS" }, { value: "http", label: "HTTP · LAN only" }]
                  foreground: root.foreground
                  onChanged: function(nextValue) {
                    portField.text = nextValue === "https" ? "443" : "80"
                  }
                }
                TextField {
                  id: portField
                  width: parent.width - transportDropdown.width - parent.spacing
                  text: "443"
                  placeholderText: "Port"
                  foreground: root.foreground
                  validator: IntValidator { bottom: 1; top: 65535 }
                }
              }

              Dropdown {
                id: tlsDropdown
                width: parent.width
                visible: transportDropdown.value === "https"
                showLabel: false
                value: "verify"
                options: [
                  { value: "verify", label: "Verify TLS certificate" },
                  { value: "insecure", label: "Allow self-signed · trusted LAN only" }
                ]
                foreground: root.foreground
              }

              TextField { id: usernameField; width: parent.width; text: "admin"; placeholderText: "Local device username"; foreground: root.foreground }
              TextField { id: passwordField; width: parent.width; password: true; placeholderText: "Password · stored in desktop keyring"; foreground: root.foreground }
              TextField { id: displayNameField; width: parent.width; placeholderText: "Display name · optional"; foreground: root.foreground }

              Text {
                width: parent.width
                text: transportDropdown.value === "http"
                  ? "This connection is not encrypted. Prefer HTTPS when supported."
                  : tlsDropdown.value === "insecure"
                    ? "Certificate validation is disabled. Use only on a trusted local network."
                    : "Use a dedicated least-privilege local Reolink user where supported."
                color: transportDropdown.value === "http" || tlsDropdown.value === "insecure"
                  ? Color.urgent : Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              Button {
                width: parent.width
                enabled: root.effectiveService && !root.effectiveService.addInProgress
                text: root.effectiveService && root.effectiveService.addInProgress
                  ? "Checking…" : "Test & Add Securely"
                iconText: "󰄀"
                foreground: root.foreground
                selected: true
                bordered: true
                focusable: true
                onClicked: root.submitAdd()
              }
            }
          }

          Flickable {
            visible: root.cameras.length > 0 && !root.showAddForm
            width: parent.width
            height: cameraSelector.implicitHeight
            contentWidth: cameraSelector.implicitWidth
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: cameraSelector
              spacing: Style.space(6)
              Repeater {
                model: root.cameras
                delegate: Button {
                  required property var modelData
                  text: modelData.name + (modelData.online ? "" : " · Offline")
                  foreground: root.foreground
                  selected: root.effectiveService && root.effectiveService.selectedCameraId === modelData.id
                  bordered: true
                  onClicked: if (root.effectiveService) root.effectiveService.selectCamera(modelData.id)
                }
              }
            }
          }

          Item {
            visible: root.selectedCamera && !root.showAddForm
            width: parent.width
            height: visible ? selectedContent.implicitHeight : 0

            Column {
              id: selectedContent
              width: parent.width
              spacing: Style.space(11)

              Row {
                width: parent.width
                spacing: Style.space(8)
                Column {
                  width: parent.width - refreshButton.width - parent.spacing
                  Text {
                    text: root.selectedCamera ? root.selectedCamera.name : ""
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }
                  Text {
                    text: root.selectedCamera
                      ? (root.selectedCamera.online ? "Online" : "Offline")
                        + (root.selectedCamera.model ? " · " + root.selectedCamera.model : "") : ""
                    color: Qt.darker(root.foreground, 1.45)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
                PanelActionButton {
                  id: refreshButton
                  iconText: "󰑐"
                  tooltipText: "Refresh snapshot"
                  foreground: root.foreground
                  onClicked: if (root.effectiveService) root.effectiveService.requestSnapshot(root.selectedCamera.id)
                }
              }

              BorderSurface {
                width: parent.width
                height: Math.round(width * 9 / 16)
                color: Util.alpha(root.foreground, 0.04)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                radius: Style.cornerRadius
                clip: true

                Image {
                  anchors.fill: parent
                  visible: root.selectedCamera && root.selectedCamera.snapshotPath !== ""
                  source: visible ? "file://" + root.selectedCamera.snapshotPath + "?v=" + root.selectedCamera.snapshotUpdatedAt : ""
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                }

                Column {
                  anchors.centerIn: parent
                  visible: !root.selectedCamera || root.selectedCamera.snapshotPath === ""
                  spacing: Style.space(6)
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰄀"; color: Qt.darker(root.foreground, 1.5); font.family: root.fontFamily; font.pixelSize: Style.font.display }
                  Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Snapshot preview"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                }

                BorderSurface {
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  anchors.margins: Style.space(8)
                  width: snapshotLabel.implicitWidth + Style.space(12)
                  height: snapshotLabel.implicitHeight + Style.space(7)
                  color: Util.alpha(Color.background, 0.78)
                  radius: Style.cornerRadius
                  Text {
                    id: snapshotLabel
                    anchors.centerIn: parent
                    text: root.selectedCamera && root.selectedCamera.snapshotUpdatedAt
                      ? "Snapshot · " + Time.relative(root.selectedCamera.snapshotUpdatedAt, Date.now()) : "Snapshot preview"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                Button {
                  width: (parent.width - parent.spacing) / 2
                  text: "Fluent Live"
                  foreground: root.foreground
                  bordered: true
                  enabled: root.selectedCamera && root.selectedCamera.capabilities.stream.rtspEnabled
                    && root.selectedCamera.capabilities.stream.fluent
                  onClicked: if (root.effectiveService) root.effectiveService.launchLive("sub")
                }
                Button {
                  width: (parent.width - parent.spacing) / 2
                  text: "Clear Live"
                  foreground: root.foreground
                  bordered: true
                  enabled: root.selectedCamera && root.selectedCamera.capabilities.stream.rtspEnabled
                    && root.selectedCamera.capabilities.stream.clear
                  onClicked: if (root.effectiveService) root.effectiveService.launchLive("main")
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                Button {
                  width: (parent.width - parent.spacing) / 2
                  text: "Refresh Snapshot"
                  foreground: root.foreground
                  bordered: true
                  onClicked: if (root.effectiveService) root.effectiveService.requestSnapshot(root.selectedCamera.id)
                }
                Button {
                  width: (parent.width - parent.spacing) / 2
                  text: root.effectiveService && root.effectiveService.snapshotExportInProgress
                    ? "Saving…" : "Save Photo"
                  foreground: root.foreground
                  bordered: true
                  enabled: root.selectedCamera && root.selectedCamera.snapshotPath !== ""
                    && root.effectiveService && !root.effectiveService.snapshotExportInProgress
                  onClicked: if (root.effectiveService) root.effectiveService.exportSnapshot(root.selectedCamera.id)
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: [
                    { key: "events", label: "Events" },
                    { key: "recordings", label: "Recordings" },
                    { key: "controls", label: "Controls" },
                    { key: "devices", label: "Devices" }
                  ]
                  delegate: Button {
                    required property var modelData
                    width: root.tabButtonWidth()
                    text: modelData.label
                    foreground: root.foreground
                    selected: root.view === modelData.key
                    onClicked: {
                      root.view = modelData.key
                      if (modelData.key === "events" && root.effectiveService) root.effectiveService.markEventsViewed()
                      if (modelData.key === "recordings" && root.effectiveService) root.effectiveService.searchRecordings()
                    }
                  }
                }
              }

              Column {
                visible: root.view === "events"
                width: parent.width
                spacing: Style.space(5)
                PanelSectionHeader { text: "RECENT EVENTS"; foreground: root.foreground; fontFamily: root.fontFamily }
                Text {
                  visible: root.effectiveService && root.effectiveService.events.length === 0
                  text: "No recent events. Event polling continues while this panel is closed."
                  width: parent.width
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Repeater {
                  model: root.effectiveService ? root.effectiveService.events.slice(0, 12) : []
                  delegate: Row {
                    id: eventRow
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(8)
                    Text { width: parent.width * 0.35; text: Events.label(eventRow.modelData.type); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                    Text { width: parent.width * 0.35; text: Time.clock(eventRow.modelData.timestamp); color: Qt.darker(root.foreground, 1.45); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Button {
                      text: "View"
                      foreground: root.foreground
                      onClicked: {
                        if (!root.effectiveService) return
                        if (root.effectiveService.viewEvent(eventRow.modelData)) root.view = "overview"
                      }
                    }
                  }
                }
              }

              Column {
                visible: root.view === "recordings"
                width: parent.width
                spacing: Style.space(6)
                PanelSectionHeader { text: "TODAY'S RECORDINGS"; foreground: root.foreground; fontFamily: root.fontFamily }
                Text {
                  visible: !root.selectedCamera || !root.selectedCamera.capabilities.recordings
                  text: "Recording search is unavailable on this device or account."
                  width: parent.width
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
                Text {
                  visible: root.selectedCamera && root.selectedCamera.capabilities.recordings
                    && root.effectiveService && root.effectiveService.recordings.length === 0
                  text: "No recordings found today."
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Repeater {
                  model: root.effectiveService ? root.effectiveService.recordings.slice(0, 12) : []
                  delegate: Row {
                    id: recordingRow
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(8)
                    Text { width: parent.width - playRecording.width - parent.spacing; text: recordingRow.modelData.type + " · " + recordingRow.modelData.name; elide: Text.ElideRight; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                    Button { id: playRecording; text: "Play"; foreground: root.foreground; onClicked: if (root.effectiveService) root.effectiveService.playRecording(recordingRow.modelData) }
                  }
                }
              }

              Column {
                visible: root.view === "controls"
                width: parent.width
                spacing: Style.space(8)
                PanelSectionHeader { text: "CAPABILITY-AWARE CONTROLS"; foreground: root.foreground; fontFamily: root.fontFamily }

                Text {
                  visible: root.selectedCamera && !root.selectedCamera.capabilities.ptz.enabled
                    && !root.selectedCamera.capabilities.spotlight && !root.selectedCamera.capabilities.siren
                  width: parent.width
                  text: "This camera does not report supported physical controls."
                  color: Qt.darker(root.foreground, 1.45)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Grid {
                  visible: root.selectedCamera && root.selectedCamera.capabilities.ptz.enabled
                  columns: 3
                  spacing: Style.space(5)
                  anchors.horizontalCenter: parent.horizontalCenter
                  Repeater {
                    model: [
                      { label: "", action: "" }, { label: "▲", action: "Up" }, { label: "", action: "" },
                      { label: "◀", action: "Left" }, { label: "■", action: "Stop" }, { label: "▶", action: "Right" },
                      { label: "", action: "" }, { label: "▼", action: "Down" }, { label: "", action: "" }
                    ]
                    delegate: BorderSurface {
                      id: ptzButton
                      required property var modelData
                      width: Style.space(46)
                      height: Style.space(38)
                      color: ptzButton.modelData.action ? Util.alpha(root.foreground, 0.05) : "transparent"
                      borderSpec: ptzButton.modelData.action ? Border.controlSpec("normal", root.foreground, Color.accent) : Border.none()
                      radius: Style.cornerRadius
                      Text { anchors.centerIn: parent; text: ptzButton.modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title }
                      MouseArea {
                        anchors.fill: parent
                        enabled: ptzButton.modelData.action !== ""
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: {
                          if (!root.effectiveService) return
                          if (ptzButton.modelData.action === "Stop") root.effectiveService.stopPtz()
                          else root.effectiveService.startPtz(ptzButton.modelData.action)
                        }
                        onReleased: if (root.effectiveService && ptzButton.modelData.action !== "Stop") root.effectiveService.stopPtz()
                        onCanceled: if (root.effectiveService && ptzButton.modelData.action !== "Stop") root.effectiveService.stopPtz()
                      }
                    }
                  }
                }

                Row {
                  visible: root.selectedCamera && root.selectedCamera.capabilities.ptz.zoom
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(8)
                  Button { text: "− Zoom"; foreground: root.foreground; bordered: true; onClicked: if (root.effectiveService) root.effectiveService.changeZoom(-1) }
                  Button { text: "+ Zoom"; foreground: root.foreground; bordered: true; onClicked: if (root.effectiveService) root.effectiveService.changeZoom(1) }
                }

                Flow {
                  visible: root.selectedCamera && root.selectedCamera.capabilities.ptz.presets
                    && root.selectedCamera.presets && root.selectedCamera.presets.length > 0
                  width: parent.width
                  spacing: Style.space(6)
                  Repeater {
                    model: root.selectedCamera && root.selectedCamera.presets ? root.selectedCamera.presets : []
                    delegate: Button {
                      required property var modelData
                      text: modelData.name
                      foreground: root.foreground
                      bordered: true
                      onClicked: if (root.effectiveService) root.effectiveService.gotoPreset(modelData.id)
                    }
                  }
                }

                Toggle {
                  visible: root.selectedCamera && root.selectedCamera.capabilities.spotlight
                  width: parent.width
                  label: "Spotlight"
                  description: "Physical camera light"
                  checked: root.spotlightOn
                  foreground: root.foreground
                  onClicked: {
                    root.spotlightOn = !root.spotlightOn
                    if (root.effectiveService) root.effectiveService.setSpotlight(root.spotlightOn)
                  }
                }

                Button {
                  visible: root.selectedCamera && root.selectedCamera.capabilities.siren
                  width: parent.width
                  text: root.sirenActive ? "Stop siren" : "Activate siren…"
                  foreground: root.sirenActive ? Color.urgent : root.foreground
                  bordered: true
                  onClicked: {
                    if (root.sirenActive) {
                      root.sirenActive = false
                      if (root.effectiveService) root.effectiveService.setSiren(false)
                    } else root.sirenConfirmation = true
                  }
                }
              }

              Column {
                visible: root.view === "devices"
                width: parent.width
                spacing: Style.space(7)
                PanelSectionHeader { text: "CONFIGURED ENDPOINTS"; foreground: root.foreground; fontFamily: root.fontFamily }
                Repeater {
                  model: root.effectiveService ? root.effectiveService.hosts : []
                  delegate: BorderSurface {
                    id: deviceRow
                    required property var modelData
                    width: parent.width
                    height: Style.space(54)
                    color: Util.alpha(root.foreground, 0.035)
                    radius: Style.cornerRadius
                    Row {
                      anchors.fill: parent
                      anchors.margins: Style.space(9)
                      spacing: Style.space(8)
                      Column {
                        width: parent.width - forgetHost.width - parent.spacing
                        Text { text: deviceRow.modelData.displayName; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
                        Text { text: deviceRow.modelData.address + " · " + deviceRow.modelData.transport.toUpperCase(); color: Qt.darker(root.foreground, 1.45); font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                      }
                      PanelActionButton {
                        id: forgetHost
                        iconText: "󰆴"
                        tooltipText: "Forget device"
                        foreground: root.foreground
                        hoverColor: Color.urgent
                        onClicked: {
                          root.removeHostId = String(deviceRow.modelData.id)
                          root.removeConfirmation = true
                        }
                      }
                    }
                  }
                }
                Button {
                  width: parent.width
                  text: "Forget all devices and local camera data"
                  foreground: Color.urgent
                  bordered: true
                  onClicked: root.forgetAllConfirmation = true
                }
              }
            }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        opened: root.sirenConfirmation
        message: "Activate siren on " + (root.selectedCamera ? root.selectedCamera.name : "this camera") + "?"
        confirmText: "Activate"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.sirenConfirmation = false
        onConfirmed: {
          root.sirenConfirmation = false
          root.sirenActive = true
          if (root.effectiveService) root.effectiveService.setSiren(true)
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        opened: root.removeConfirmation
        message: "Forget this device and its stored password and snapshots?"
        confirmText: "Forget device"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: { root.removeConfirmation = false; root.removeHostId = "" }
        onConfirmed: {
          root.removeConfirmation = false
          if (root.effectiveService && root.removeHostId) root.effectiveService.removeHost(root.removeHostId)
          root.removeHostId = ""
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        opened: root.forgetAllConfirmation
        message: "Forget every device, stored password, snapshot, and local setting?"
        confirmText: "Forget everything"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onCanceled: root.forgetAllConfirmation = false
        onConfirmed: {
          root.forgetAllConfirmation = false
          if (root.effectiveService) root.effectiveService.forgetAll()
        }
      }
    }
  }
}
