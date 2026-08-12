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
  property var deviceLayouts: []
  property var configuredLayouts: []
  property var layouts: []
  property int activeLayoutIndex: 0
  property int cursorIndex: 0
  property bool cursorActive: false
  property string layoutFull: ""
  property string layoutLabel: ""
  property bool multipleLayouts: true
  property real pulseOpacity: 1
  property real pulseScale: 1

  function typingKeyboards(keyboards) {
    var physical = keyboards.filter(function(keyboard) {
      return !String(keyboard.name).startsWith("hl-virtual-keyboard")
    })
    var typing = physical.filter(function(keyboard) {
      var name = String(keyboard.name)
      return !name.endsWith("-system-control")
        && !name.endsWith("-consumer-control")
        && name !== "video-bus"
        && !name.startsWith("power-button")
    })
    return typing.length > 0 ? typing : physical
  }

  function selectKeyboard(keyboards) {
    var typing = root.typingKeyboards(keyboards)
    return typing.find(function(keyboard) {
        return keyboard.name === root.keyboardName
      })
      || typing.find(function(keyboard) { return keyboard.main })
      || typing[0]
  }

  function updateKeyboards(keyboards) {
    var keyboard = root.selectKeyboard(keyboards)
    if (!keyboard || !keyboard.active_keymap) return

    var nextLayouts = String(keyboard.layout || "").split(",").filter(Boolean)
    var index = Number(keyboard.active_layout_index || 0)

    root.keyboardName = String(keyboard.name || "")
    root.keyboardNames = root.typingKeyboards(keyboards).map(function(item) {
      return String(item.name || "")
    }).filter(Boolean)
    root.deviceLayouts = nextLayouts
    root.activeLayoutIndex = index
    root.layoutFull = String(keyboard.active_keymap)
    root.updateLayouts()
  }

  function updateConfiguredLayouts(raw) {
    try {
      var value = String(JSON.parse(raw || "{}").str || "")
      root.configuredLayouts = value.split(",").filter(Boolean)
    } catch (error) {
      root.configuredLayouts = []
    }
    root.updateLayouts()
  }

  function updateLayouts() {
    var nextLayouts = root.configuredLayouts.length > 0
      ? root.configuredLayouts
      : root.deviceLayouts
    var nextLabel = nextLayouts[root.activeLayoutIndex]
      ? String(nextLayouts[root.activeLayoutIndex]).toUpperCase()
      : root.layoutFull.split(/\s+/)[0].substring(0, 3).toUpperCase()
    var changed = root.layoutLabel !== "" && root.layoutLabel !== nextLabel

    root.layouts = nextLayouts
    root.layoutLabel = nextLabel
    root.multipleLayouts = nextLayouts.length > 1
    if (changed) pulseAnimation.restart()
  }

  function refresh() {
    if (!queryProcess.running) queryProcess.running = true
    if (!layoutProcess.running) layoutProcess.running = true
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
      if (!event) return
      var name = String(event.name || "")
      if (name.indexOf("activelayout") !== -1 || name === "configreloaded")
        root.refresh()
    }
  }

  Process {
    id: layoutProcess
    command: ["hyprctl", "-j", "getoption", "input:kb_layout"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateConfiguredLayouts(text)
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
          to: 1.16
          duration: 325
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          target: root
          property: "pulseScale"
          from: 1.16
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
    text: ""
    hasVisualContent: root.layoutLabel !== ""
    labelVisible: false
    fixedWidth: Math.max(12, labelProbe.implicitWidth + Style.space(12))
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
    onWheelMoved: function(delta) {
      root.cycle(delta > 0 ? "next" : "prev")
    }
  }

  Text {
    id: labelProbe
    visible: false
    text: root.layoutLabel
    font.family: button.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    id: pulseLabel
    anchors.centerIn: button
    text: root.layoutLabel
    color: pulseAnimation.running ? "#2aa198" : button.foreground
    opacity: root.pulseOpacity
    scale: root.pulseScale
    transformOrigin: Item.Center
    font.family: button.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: pulseAnimation.running
    renderType: Text.NativeRendering
    layer.enabled: pulseAnimation.running
    layer.smooth: true

    Behavior on color {
      ColorAnimation { duration: 160 }
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
