pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "lib/Validation.js" as Validation
import "lib/ReolinkCommands.js" as Commands
import "lib/ReolinkModel.js" as Model
import "lib/EventNormalizer.js" as Events
import "lib/NotificationCommand.js" as NotificationCommand

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  property var barWidgetRegistry: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.rodrix2000.reolink-cameras"
  readonly property string pluginRoot: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string httpHelper: pluginRoot + "/scripts/reolink-http"
  readonly property string playerHelper: pluginRoot + "/scripts/reolink-player"
  readonly property string snapshotExportHelper: pluginRoot + "/scripts/reolink-snapshot-export"
  readonly property string secretHelper: pluginRoot + "/scripts/reolink-secret"
  readonly property string configHelper: pluginRoot + "/scripts/reolink-config"

  property bool configReady: false
  property var config: Model.defaultConfig()
  property var hosts: []
  property var cleanupHostIds: []
  property var cameras: []
  property var hostStates: ({})
  property var events: []
  property var recordings: []
  property string selectedCameraId: ""
  property bool previewActive: false
  property int previewOwners: 0
  property string lastError: ""
  property string notice: ""
  property var runtimes: ({})
  property bool addInProgress: false
  property bool snapshotExportInProgress: false

  readonly property int onlineCount: {
    var count = 0
    for (var index = 0; index < cameras.length; index += 1) if (cameras[index].online) count += 1
    return count
  }
  readonly property int unseenCount: {
    var count = 0
    for (var index = 0; index < events.length; index += 1) if (!events[index].viewed) count += 1
    return count
  }
  readonly property var selectedCamera: cameraForId(selectedCameraId)
  readonly property string tooltipText: {
    if (!configReady) return "Reolink Cameras — starting"
    if (!hosts.length) return "Reolink Cameras — add a camera or recorder"
    if (unseenCount > 0) return "Reolink Cameras — " + unseenCount + " unseen event" + (unseenCount === 1 ? "" : "s")
    if (onlineCount < cameras.length) return "Reolink Cameras — " + (cameras.length - onlineCount) + " offline"
    return "Reolink Cameras — " + onlineCount + " online"
  }

  signal cameraDataChanged()
  signal addCompleted(bool ok, string message)

  function cameraForId(cameraId) {
    for (var index = 0; index < cameras.length; index += 1)
      if (cameras[index].id === cameraId) return cameras[index]
    return null
  }

  function cameraForHostChannel(hostId, channel) {
    for (var index = 0; index < cameras.length; index += 1)
      if (cameras[index].hostId === hostId && Number(cameras[index].channel) === Number(channel))
        return cameras[index]
    return null
  }

  function hostForId(hostId) {
    for (var index = 0; index < hosts.length; index += 1)
      if (hosts[index].id === hostId) return hosts[index]
    return null
  }

  function runtimeForHost(hostId) {
    return runtimes[String(hostId)] || null
  }

  function registerRuntime(hostId, runtime) {
    var next = ({})
    for (var key in runtimes) next[key] = runtimes[key]
    next[String(hostId)] = runtime
    runtimes = next
  }

  function unregisterRuntime(hostId, runtime) {
    if (runtimes[String(hostId)] !== runtime) return
    var next = ({})
    for (var key in runtimes) if (key !== String(hostId)) next[key] = runtimes[key]
    runtimes = next
  }

  function setHostState(hostId, state, message) {
    var next = ({})
    for (var key in hostStates) next[key] = hostStates[key]
    next[String(hostId)] = { state: state, message: message || "", updatedAt: Date.now() }
    hostStates = next
  }

  function updateHostCameras(hostId, values) {
    cameras = Model.replaceHostCameras(cameras, hostId, values)
    if ((!selectedCameraId || !cameraForId(selectedCameraId)) && cameras.length)
      selectedCameraId = cameras[0].id
    cameraDataChanged()
  }

  function updateCamera(cameraId, patch) {
    cameras = Model.updateCamera(cameras, cameraId, patch)
    cameraDataChanged()
  }

  function selectCamera(cameraId) {
    if (cameraForId(cameraId)) selectedCameraId = cameraId
  }

  function setPanelOpen(value) {
    previewOwners = Math.max(0, previewOwners + (value === true ? 1 : -1))
    previewActive = previewOwners > 0
    if (previewActive && selectedCameraId) requestSnapshot(selectedCameraId)
  }

  function markHostOffline(hostId) {
    cameras = Model.markHostOffline(cameras, hostId)
    cameraDataChanged()
  }

  function requestSnapshot(cameraId) {
    var camera = cameraForId(cameraId)
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime) runtime.requestSnapshot(camera)
  }

  function exportSnapshot(cameraId) {
    var camera = cameraForId(cameraId)
    if (!camera || !camera.snapshotPath) {
      lastError = "Refresh the camera snapshot before saving it."
      return
    }
    if (snapshotExportProcess.running) {
      lastError = "Another snapshot export is already in progress."
      return
    }
    lastError = ""
    notice = "Saving snapshot to Pictures…"
    snapshotExportInProgress = true
    snapshotExportProcess.input = JSON.stringify({
      operation: "export", hostId: camera.hostId, channel: Number(camera.channel)
    })
    snapshotExportProcess.running = true
  }

  function refreshAll() {
    for (var hostId in runtimes) if (runtimes[hostId]) runtimes[hostId].refresh()
  }

  function startPtz(direction) {
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime && camera.capabilities.ptz.enabled) runtime.startPtz(camera, direction)
  }

  function stopPtz() {
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime) runtime.stopPtz(camera)
  }

  function stopAllPtz() {
    for (var hostId in runtimes) if (runtimes[hostId]) runtimes[hostId].stopPtz(null)
  }

  function gotoPreset(presetId) {
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime && camera.capabilities.ptz.presets) runtime.gotoPreset(camera, presetId)
  }

  function changeZoom(direction) {
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime && camera.capabilities.ptz.zoom) runtime.changeZoom(camera, direction)
  }

  function setSpotlight(enabled) {
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime && camera.capabilities.spotlight) runtime.setSpotlight(camera, enabled)
  }

  function setSiren(enabled) {
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime && camera.capabilities.siren) runtime.setSiren(camera, enabled)
  }

  function searchRecordings() {
    recordings = []
    var camera = selectedCamera
    var runtime = camera ? runtimeForHost(camera.hostId) : null
    if (runtime && camera.capabilities.recordings) runtime.searchRecordings(camera)
  }

  function playRecording(recording) {
    if (!recording) return
    var runtime = runtimeForHost(recording.hostId)
    if (runtime) runtime.playRecording(recording)
  }

  function viewEvent(event) {
    if (!event) return false
    var camera = cameraForHostChannel(String(event.hostId || ""), Number(event.channel))
    if (!camera) {
      lastError = "This event belongs to a camera that is no longer configured."
      return false
    }
    var runtime = runtimeForHost(camera.hostId)
    if (!runtime) {
      lastError = "The event camera is not currently available."
      return false
    }
    selectedCameraId = camera.id
    requestSnapshot(camera.id)
    if (!camera.capabilities.recordings) {
      lastError = "Recording playback is unavailable; the current snapshot was refreshed instead."
      return true
    }
    notice = "Finding the " + Events.label(event.type).toLowerCase() + " recording…"
    lastError = ""
    runtime.openEventRecording(event)
    return true
  }

  function launchLive(stream) {
    var camera = selectedCamera
    var host = camera ? hostForId(camera.hostId) : null
    if (!camera || !host || playerProcess.running) return
    if (!camera.capabilities.stream.rtspEnabled) return
    if (stream === "sub" && !camera.capabilities.stream.fluent) return
    if (stream === "main" && !camera.capabilities.stream.clear) return
    var payload = {
      kind: "live", hostId: host.id, address: host.address, username: host.username,
      rtspPort: host.rtspPort, channel: camera.streamChannel, stream: stream
    }
    playerProcess.input = JSON.stringify(payload)
    playerProcess.running = true
  }

  function publishEvents(newEvents) {
    if (!newEvents || !newEvents.length) return
    var merged = newEvents.concat(events).slice(0, 100)
    events = merged
    for (var index = 0; index < newEvents.length; index += 1) {
      var event = newEvents[index]
      var preferences = config.preferences && config.preferences.notify ? config.preferences.notify : ({})
      if (preferences[event.type] === true) queueNotification(event)
    }
  }

  function markEventsViewed() {
    var next = []
    for (var index = 0; index < events.length; index += 1) {
      var event = events[index]
      var copy = ({})
      for (var key in event) copy[key] = event[key]
      copy.viewed = true
      next.push(copy)
    }
    events = next
  }

  function clearEvents() {
    events = []
    notificationQueue = []
    lastError = ""
    notice = "Recent events cleared."
  }

  function queueNotification(event) {
    var notification = Events.notification(event.type)
    var queue = notificationQueue.slice()
    queue.push(notification)
    notificationQueue = queue
    drainNotifications()
  }

  property var notificationQueue: []
  function drainNotifications() {
    if (notificationProcess.running || !notificationQueue.length) return
    var queue = notificationQueue.slice()
    var next = queue.shift()
    notificationQueue = queue
    notificationProcess.command = NotificationCommand.build(pluginId, next)
    notificationProcess.running = true
  }

  function addHost(details, password) {
    if (addInProgress) {
      lastError = "Another secure credential operation is already in progress."
      addCompleted(false, lastError)
      return
    }
    lastError = ""
    notice = "Checking the camera…"
    var validation = Validation.validateEndpoint(details)
    if (!validation.ok) { notice = ""; lastError = validation.error; addCompleted(false, validation.error); return }
    if (String(password).length < 1 || String(password).length > 4096
        || /[\u0000-\u001f\u007f]/.test(String(password))) {
      notice = ""; lastError = "Password must be 1 to 4096 characters without control characters."
      addCompleted(false, lastError); return
    }
    if (Validation.savedFieldDuplicatesSecret(details, password)) {
      notice = ""; lastError = "The password must not duplicate a saved endpoint field."
      addCompleted(false, lastError); return
    }
    var endpoint = validation.value
    if (!Model.canBeginCredentialMutation(addInProgress, cleanupHostIds, endpoint.id)) {
      notice = ""
      lastError = "Resolve pending credential cleanup before adding another device."
      addCompleted(false, lastError)
      return
    }
    // Reserve the single credential transaction before the first async helper.
    // This covers overlapping submissions from multiple panel instances.
    addInProgress = true
    var reservation = Model.addCleanupHostId(cleanupHostIds, endpoint.id)
    saveConfigState(hosts, reservation, function(reserved, reservationMessage) {
      if (!reserved) {
        root.addInProgress = false
        root.notice = ""
        root.lastError = reservationMessage
        root.addCompleted(false, reservationMessage)
        return
      }
      root.cleanupHostIds = reservation
      runSecret({ operation: "store", hostId: endpoint.id, password: String(password) }, function(ok, result) {
        if (!ok) {
          root.cleanupFailedAdd(endpoint.id, result)
          return
        }
        root.testEndpoint(endpoint, function(testOk, testMessage) {
          if (!testOk) {
            root.cleanupFailedAdd(endpoint.id, testMessage)
            return
          }
          var nextHosts = []
          for (var index = 0; index < root.hosts.length; index += 1)
            if (root.hosts[index].id !== endpoint.id) nextHosts.push(root.hosts[index])
          nextHosts.push(endpoint)
          var nextCleanup = Model.removeCleanupHostId(root.cleanupHostIds, endpoint.id)
          root.saveConfigState(nextHosts, nextCleanup, function(saveOk, saveMessage) {
            if (!saveOk) { root.cleanupFailedAdd(endpoint.id, saveMessage); return }
            root.hosts = nextHosts
            root.cleanupHostIds = nextCleanup
            root.notice = "Camera added securely."
            root.lastError = ""
            root.addInProgress = false
            root.addCompleted(true, "Camera added securely.")
          })
        })
      })
    })
  }

  function cleanupFailedAdd(hostId, primaryMessage) {
    runSecret({ operation: "clear", hostId: hostId }, function(clearOk, clearMessage) {
      if (clearOk) {
        var nextCleanup = Model.removeCleanupHostId(root.cleanupHostIds, hostId)
        root.saveConfigState(root.hosts, nextCleanup, function(saveOk, saveMessage) {
          var message = String(primaryMessage)
          if (saveOk) root.cleanupHostIds = nextCleanup
          else message += " The password was removed, but cleanup state remains pending: " + String(saveMessage)
          root.addInProgress = false
          root.notice = ""
          root.lastError = message
          root.addCompleted(false, message)
        })
        return
      }
      root.cleanupHostIds = Model.addCleanupHostId(root.cleanupHostIds, hostId)
      root.saveConfig(function(saveOk, saveMessage) {
        var message = String(primaryMessage) + " The stored password could not be removed; use Retry credential cleanup."
        if (!saveOk) message += " Cleanup state could not be saved: " + String(saveMessage)
        root.addInProgress = false
        root.notice = ""
        root.lastError = message
        root.addCompleted(false, message)
      })
    })
  }

  function retryCredentialCleanup() {
    if (addInProgress) { lastError = "Another secure credential operation is already in progress."; return }
    var pending = cleanupHostIds.slice()
    if (!pending.length) return
    addInProgress = true
    var values = []
    for (var index = 0; index < pending.length; index += 1) values.push({ id: pending[index] })
    notice = "Retrying secure credential cleanup…"
    clearHostSecrets(values, 0, function(ok, message) {
      if (!ok) { root.addInProgress = false; root.notice = ""; root.lastError = message; return }
      root.cleanupHostIds = []
      root.saveConfig(function(saveOk, saveMessage) {
        root.addInProgress = false
        root.notice = saveOk ? "Pending keyring credentials were removed." : ""
        root.lastError = saveOk ? "" : saveMessage
      })
    })
  }

  function removeHost(hostId) {
    if (addInProgress) { lastError = "Another secure credential operation is already in progress."; return }
    addInProgress = true
    notice = "Forgetting device…"
    runSecret({ operation: "clear", hostId: hostId }, function(secretOk, secretMessage) {
      if (!secretOk) { root.addInProgress = false; root.notice = ""; root.lastError = secretMessage; return }
      var nextHosts = []
      for (var index = 0; index < root.hosts.length; index += 1)
        if (root.hosts[index].id !== hostId) nextHosts.push(root.hosts[index])
      root.hosts = nextHosts
      root.cleanupHostIds = Model.removeCleanupHostId(root.cleanupHostIds, hostId)
      root.cameras = Model.replaceHostCameras(root.cameras, hostId, [])
      root.events = root.events.filter(function(event) { return event.hostId !== hostId })
      root.recordings = root.recordings.filter(function(recording) { return recording.hostId !== hostId })
      if (!root.cameraForId(root.selectedCameraId))
        root.selectedCameraId = root.cameras.length ? root.cameras[0].id : ""
      root.saveConfig(function(saveOk, saveMessage) {
        if (!saveOk) { root.addInProgress = false; root.notice = ""; root.lastError = saveMessage; return }
        root.runConfig({ operation: "purge-host", hostId: hostId }, function(purgeOk, purgeMessage) {
          root.addInProgress = false
          root.notice = purgeOk ? "Device forgotten." : ""
          root.lastError = purgeOk ? "" : purgeMessage
        })
      })
    })
  }

  function clearHostSecrets(values, index, callback) {
    if (index >= values.length) { callback(true, ""); return }
    runSecret({ operation: "clear", hostId: values[index].id }, function(ok, message) {
      if (!ok) { callback(false, message); return }
      root.clearHostSecrets(values, index + 1, callback)
    })
  }

  function forgetAll() {
    if (addInProgress) { lastError = "Another secure credential operation is already in progress."; return }
    addInProgress = true
    var oldHosts = hosts.slice()
    for (var cleanupIndex = 0; cleanupIndex < cleanupHostIds.length; cleanupIndex += 1) {
      var cleanupId = cleanupHostIds[cleanupIndex]
      var present = false
      for (var hostIndex = 0; hostIndex < oldHosts.length; hostIndex += 1)
        if (oldHosts[hostIndex].id === cleanupId) present = true
      if (!present) oldHosts.push({ id: cleanupId })
    }
    notice = "Clearing credentials and local camera data…"
    clearHostSecrets(oldHosts, 0, function(secretsOk, secretsMessage) {
      if (!secretsOk) { root.addInProgress = false; root.notice = ""; root.lastError = secretsMessage; return }
      root.runConfig({ operation: "clear" }, function(ok, message) {
        if (ok) {
          root.hosts = []
          root.cleanupHostIds = []
          root.cameras = []
          root.events = []
          root.recordings = []
          root.selectedCameraId = ""
          root.config = Model.defaultConfig()
        }
        root.addInProgress = false
        root.notice = ok ? "All local Reolink data was forgotten." : ""
        root.lastError = ok ? "" : message
      })
    })
  }

  function saveConfig(callback) {
    saveConfigState(hosts, cleanupHostIds, callback)
  }

  function saveConfigState(hostValues, cleanupValues, callback) {
    var next = {
      version: 1,
      hosts: hostValues,
      cleanupHostIds: cleanupValues,
      preferences: config.preferences || Model.defaultConfig().preferences
    }
    if (Validation.configHasForbiddenSecretKey(next)) {
      if (callback) callback(false, "Refused to persist a secret field.")
      return
    }
    runConfig({ operation: "save", config: next }, function(ok, message) {
      if (ok) root.config = next
      if (callback) callback(ok, message)
    })
  }

  property var configQueue: []
  function runConfig(payload, callback) {
    var queue = configQueue.slice()
    queue.push({ payload: payload, callback: callback })
    configQueue = queue
    drainConfig()
  }

  function drainConfig() {
    if (configProcess.running || !configQueue.length || pluginRoot === "") return
    var queue = configQueue.slice()
    var item = queue.shift()
    configQueue = queue
    configProcess.callback = item.callback
    configProcess.input = JSON.stringify(item.payload)
    configProcess.running = true
  }

  property var secretQueue: []
  function runSecret(payload, callback) {
    var queue = secretQueue.slice()
    queue.push({ input: JSON.stringify(payload), callback: callback })
    secretQueue = queue
    drainSecrets()
  }

  function drainSecrets() {
    if (secretProcess.running || !secretQueue.length || pluginRoot === "") return
    var queue = secretQueue.slice()
    var item = queue.shift()
    secretQueue = queue
    secretProcess.callback = item.callback
    secretProcess.input = item.input
    item.input = ""
    secretProcess.running = true
  }

  function loadConfiguration() {
    if (!pluginRoot || configProcess.running || configReady) return
    runConfig({ operation: "load" }, function(ok, message, value) {
      if (!ok) {
        root.lastError = message
        root.configReady = true
        return
      }
      root.config = value
      root.hosts = Array.isArray(value.hosts) ? value.hosts : []
      root.cleanupHostIds = Array.isArray(value.cleanupHostIds) ? value.cleanupHostIds : []
      root.configReady = true
    })
  }

  function testEndpoint(endpoint, callback) {
    if (testProcess.running) { callback(false, "Another camera test is already running."); return }
    testProcess.callback = callback
    testProcess.input = JSON.stringify(Commands.loginEnvelope(endpoint))
    testProcess.running = true
  }

  onPluginRootChanged: configLoadTimer.restart()
  Component.onCompleted: loadConfiguration()
  Component.onDestruction: {
    stopAllPtz()
    playerProcess.running = false
  }

  Instantiator {
    id: hostRuntimeInstances
    model: root.hosts
    delegate: HostRuntime {
      required property var modelData
      host: modelData
      service: root
      helperPath: root.httpHelper
      playerPath: root.playerHelper
    }
    onObjectAdded: function(index, object) {
      if (object && object.host) root.registerRuntime(object.host.id, object)
    }
    onObjectRemoved: function(index, object) {
      if (object && object.host) root.unregisterRuntime(object.host.id, object)
    }
  }

  Timer {
    id: configLoadTimer
    interval: 250
    repeat: false
    onTriggered: root.loadConfiguration()
  }

  Process {
    id: configProcess
    property string input: ""
    property var callback: null
    command: ["/usr/bin/bash", root.configHelper]
    stdinEnabled: true
    stdout: StdioCollector { id: configOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      var callbackValue = callback
      callback = null
      var parsed = null
      try { parsed = JSON.parse(String(configOutput.text || "")) } catch (error) {}
      var ok = exitStatus === 0 && exitCode === 0 && parsed !== null
      var message = ok ? "" : parsed && parsed.error ? String(parsed.error.message) : "Configuration operation failed."
      if (callbackValue) callbackValue(ok, message, parsed)
      Qt.callLater(root.drainConfig)
    }
  }

  Process {
    id: secretProcess
    property string input: ""
    property var callback: null
    command: ["/usr/bin/bash", root.secretHelper]
    stdinEnabled: true
    stdout: StdioCollector { id: secretOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      var callbackValue = callback
      callback = null
      var parsed = null
      try { parsed = JSON.parse(String(secretOutput.text || "")) } catch (error) {}
      var ok = exitStatus === 0 && exitCode === 0 && parsed && parsed.ok === true
      var message = ok ? "" : parsed && parsed.error ? String(parsed.error.message) : "Keyring operation failed."
      if (callbackValue) callbackValue(ok, message)
      Qt.callLater(root.drainSecrets)
    }
  }

  Process {
    id: testProcess
    property string input: ""
    property var callback: null
    command: ["/usr/bin/bash", root.httpHelper]
    stdinEnabled: true
    stdout: StdioCollector { id: testOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      var callbackValue = callback
      callback = null
      var parsed = null
      try { parsed = JSON.parse(String(testOutput.text || "")) } catch (error) {}
      var processOk = exitStatus === 0 && exitCode === 0
      var session = Model.loginProcessResult(parsed, Date.now(), processOk)
      var ok = processOk && session.ok
      if (callbackValue) callbackValue(ok, ok ? "" : String(session.error || "Camera test failed."))
    }
  }

  Process {
    id: playerProcess
    property string input: ""
    command: ["/usr/bin/bash", root.playerHelper]
    stdinEnabled: true
    stdout: StdioCollector { id: playerOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      if (exitStatus === 0 && exitCode === 0) return
      var parsed = null
      try { parsed = JSON.parse(String(playerOutput.text || "")) } catch (error) {}
      root.lastError = parsed && parsed.error ? String(parsed.error.message) : "Could not open mpv."
    }
  }

  Process {
    id: snapshotExportProcess
    property string input: ""
    command: ["/usr/bin/bash", root.snapshotExportHelper]
    stdinEnabled: true
    stdout: StdioCollector { id: snapshotExportOutput; waitForEnd: true }
    onStarted: { write(input + "\n"); input = "" }
    onExited: function(exitCode, exitStatus) {
      root.snapshotExportInProgress = false
      var parsed = null
      try { parsed = JSON.parse(String(snapshotExportOutput.text || "")) } catch (error) {}
      var ok = exitStatus === 0 && exitCode === 0 && parsed && parsed.ok === true
      root.notice = ok ? "Snapshot saved to " + String(parsed.path) : ""
      root.lastError = ok ? "" : parsed && parsed.error
        ? String(parsed.error.message) : "Snapshot could not be saved."
    }
  }

  Process {
    id: notificationProcess
    onExited: Qt.callLater(root.drainNotifications)
  }
}
