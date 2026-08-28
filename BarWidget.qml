pragma ComponentBehavior: Bound

import QtQuick
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.rodrix2000.reolink-cameras"

  readonly property var hostShell: root.bar && root.bar.shell ? root.bar.shell : null
  readonly property var reolinkService: hostShell && typeof hostShell.serviceFor === "function"
    ? hostShell.serviceFor(moduleName) : null
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.service = root.reolinkService
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onReolinkServiceChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || !root.reolinkService || root.reolinkService.unseenCount === 0
      ? "󰄀" : "󰄀 " + root.reolinkService.unseenCount
    tooltipText: root.reolinkService ? root.reolinkService.tooltipText : "Reolink Cameras — starting"
    active: root.opened || (root.reolinkService && root.reolinkService.unseenCount > 0)
    fixedWidth: root.vertical ? root.barSize : -1
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (root.reolinkService) root.reolinkService.refreshAll()
      } else if (buttonCode === Qt.LeftButton) {
        root.togglePanel()
      }
    }
  }
}
