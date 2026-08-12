import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy.keyboard-layout"

  property string keyboardName: ""
  property var keyboardNames: []
  property var layouts: []
  property int activeLayoutIndex: 0
  property int cursorIndex: 0
  property bool cursorActive: false
  property string layoutFull: ""
  property string layoutLabel: ""
  property bool multipleLayouts: true
  property real pulseOpacity: 1
  property real pulseScale: 1

  function physicalKeyboards(keyboards) {
    return keyboards.filter(function(keyboard) {
      return !String(keyboard.name).startsWith("hl-virtual-keyboard")
    })
  }

  function selectKeyboard(keyboards) {
    var physical = root.physicalKeyboards(keyboards)
    return physical.find(function(keyboard) { return keyboard.main })
      || physical.find(function(keyboard) {
        return keyboard.name === root.keyboardName
      })
      || physical[0]
  }

  function updateKeyboards(keyboards) {
    var keyboard = root.selectKeyboard(keyboards)
    if (!keyboard || !keyboard.active_keymap) return

    var nextLayouts = String(keyboard.layout || "").split(",").filter(Boolean)
    var index = Number(keyboard.active_layout_index || 0)
    var nextLabel = nextLayouts[index]
      ? nextLayouts[index].toUpperCase()
      : String(keyboard.active_keymap).split(/\s+/)[0].substring(0, 3).toUpperCase()
    var changed = root.layoutLabel !== "" && root.layoutLabel !== nextLabel

    root.keyboardName = String(keyboard.name || "")
    root.keyboardNames = root.physicalKeyboards(keyboards).map(function(item) {
      return String(item.name || "")
    }).filter(Boolean)
    root.layouts = nextLayouts
    root.activeLayoutIndex = index
    root.layoutFull = String(keyboard.active_keymap)
    root.layoutLabel = nextLabel
    root.multipleLayouts = nextLayouts.length > 1
    if (changed) pulseAnimation.restart()
  }

  function refresh() {
    if (!queryProcess.running) queryProcess.running = true
  }

  function switchLayouts(target) {
    if (!root.bar || root.keyboardNames.length === 0) return

    var commands = root.keyboardNames.map(function(name) {
      return "hyprctl switchxkblayout " + Util.shellQuote(name)
        + " " + Util.shellQuote(target)
    })
    root.bar.run(commands.join("; "))
    refreshTimer.restart()
  }

  function cycle(direction) {
    root.switchLayouts(direction)
  }

  function selectLayout(index) {
    if (index < 0 || index >= root.layouts.length) return
    root.switchLayouts(String(index))
    root.close()
  }

  function moveCursor(delta) {
    if (root.layouts.length === 0) return
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    root.cursorIndex = (root.cursorIndex + delta + root.layouts.length)
      % root.layouts.length
  }

  onOpenedChanged: {
    if (!opened) return
    root.cursorIndex = root.activeLayoutIndex
    root.cursorActive = false
    root.refresh()
  }

  Component.onCompleted: refresh()

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name || "").indexOf("activelayout") !== -1)
        root.refresh()
    }
  }

  Process {
    id: queryProcess
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.updateKeyboards(JSON.parse(text || "{}").keyboards || [])
        } catch (error) {
          root.layoutLabel = ""
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  SequentialAnimation {
    id: pulseAnimation
    loops: 3
    onStopped: {
      root.pulseOpacity = 1
      root.pulseScale = 1
    }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "pulseOpacity"
        from: 0.65
        to: 1
        duration: 650
        easing.type: Easing.InOutSine
      }
      SequentialAnimation {
        NumberAnimation {
          target: root
          property: "pulseScale"
          from: 1
          to: 1.08
          duration: 325
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          target: root
          property: "pulseScale"
          from: 1.08
          to: 1
          duration: 325
          easing.type: Easing.InOutSine
        }
      }
    }
  }

  visible: layoutLabel !== "" && multipleLayouts
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.layoutLabel
    active: pulseAnimation.running
    activeColor: "#2aa198"
    opacity: root.pulseOpacity
    scale: root.pulseScale
    transformOrigin: Item.Center
    fontSize: Style.font.caption
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
    onWheelMoved: function(delta) {
      root.cycle(delta > 0 ? "next" : "prev")
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(180))
    contentHeight: panel.fittedContentHeight(layoutColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: {
        if (root.cursorActive) root.selectLayout(root.cursorIndex)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: layoutColumn
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.layouts

          Button {
            required property var modelData
            required property int index
            width: layoutColumn.width
            text: String(modelData).toUpperCase()
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            selected: root.activeLayoutIndex === index
            hasCursor: root.cursorActive && root.cursorIndex === index
            onClicked: root.selectLayout(index)
            onHovered: function(hovered) {
              if (!hovered) return
              root.cursorActive = true
              root.cursorIndex = index
            }
          }
        }
      }
    }
  }
}
