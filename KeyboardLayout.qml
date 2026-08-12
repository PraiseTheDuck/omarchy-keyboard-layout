import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.ilyazar.keyboard-layout"

  readonly property string tealColor: "#2aa198"
  readonly property string purpleColor: "#a77bd8"
  readonly property string blueColor: "#3b82f6"
  readonly property string yellowColor: "#ebcb8b"
  readonly property var colorPresets: [
    { label: "Teal", value: tealColor },
    { label: "Purple", value: purpleColor },
    { label: "Blue", value: blueColor },
    { label: "Yellow", value: yellowColor }
  ]
  readonly property string keyboardConfigPath:
    Quickshell.env("HOME") + "/.config/hypr/input.lua"
  readonly property string pulseColor: normalizedPulseColor(
    setting("pulseColor", tealColor))
  readonly property string shortcutDescription:
    describeGroupOption(groupOptionFrom(effectiveKeyboardOptions))
  property bool settingsPage: false
  property bool customColorEditorVisible: false
  property string effectiveKeyboardOptions: ""
  property string xkbOptionDescriptions: ""
  property int keyboardOptionsLine: 1

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

  function isPulseColor(value) {
    return /^#[0-9a-fA-F]{6}$/.test(String(value || "").trim())
  }

  function normalizedPulseColor(value) {
    var color = String(value || "").trim().toLowerCase()
    return isPulseColor(color) ? color : tealColor
  }

  function presetForColor(value) {
    var color = normalizedPulseColor(value)
    return color === tealColor || color === purpleColor || color === blueColor
      || color === yellowColor
      ? color
      : "custom"
  }

  function groupOptionFrom(options) {
    return String(options || "").split(",").map(function(option) {
      return option.trim()
    }).find(function(option) {
      return option.startsWith("grp:")
    }) || ""
  }

  function friendlyXkbDescription(value) {
    return String(value || "")
      .replace(/\bBoth Alts together\b/g, "Both Alt keys")
      .replace(/\bBoth Ctrls together\b/g, "Both Ctrl keys")
      .replace(/\bBoth Shifts together\b/g, "Both Shift keys")
      .replace(/\bWin\b/g, "Super")
      .replace(/\s*\+\s*/g, " + ")
  }

  function describeGroupOption(option) {
    if (!option) return "Not configured"

    var lines = root.xkbOptionDescriptions.split("\n")
    for (var index = 0; index < lines.length; index++) {
      var match = lines[index].match(/^\s*(grp:\S+)\s+(.+)$/)
      if (match && match[1] === option)
        return friendlyXkbDescription(match[2])
    }

    return option
      .substring(4)
      .replace(/_toggle(?:_bidir)?$/, "")
      .replace(/_/g, " ")
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings)
      if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.bar && root.bar.shell
        && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setPulseColor(value) {
    if (!isPulseColor(value)) return
    var color = normalizedPulseColor(value)
    persistSettings({ pulseColor: color })
    customColorField.text = color
  }

  function applyPulseColor(value) {
    if (!isPulseColor(value)) return
    setPulseColor(value)
    root.close()
  }

  function selectPresetColor(value) {
    root.customColorEditorVisible = false
    setPulseColor(value)
    keyCatcher.forceActiveFocus()
  }

  function openCustomColorEditor() {
    root.customColorEditorVisible = true
    customColorField.text = root.pulseColor
    Qt.callLater(function() {
      customColorField.selectAll()
      customColorField.forceActiveFocus()
    })
  }

  function updateKeyboardOptions(raw) {
    try {
      root.effectiveKeyboardOptions
        = String(JSON.parse(raw || "{}").str || "")
    } catch (error) {
      root.effectiveKeyboardOptions = ""
    }
  }

  function updateKeyboardConfig(raw) {
    var lines = String(raw || "").split("\n")
    var commentedLine = 1

    for (var index = 0; index < lines.length; index++) {
      if (/^\s*kb_options\s*=/.test(lines[index])) {
        root.keyboardOptionsLine = index + 1
        return
      }
      if (/kb_options\s*=/.test(lines[index])) commentedLine = index + 1
    }

    root.keyboardOptionsLine = commentedLine
  }

  function openSettings() {
    root.settingsPage = true
    customColorField.text = root.pulseColor
    root.customColorEditorVisible
      = root.presetForColor(root.pulseColor) === "custom"
  }

  function closeSettings() {
    root.settingsPage = false
    root.customColorEditorVisible = false
    keyCatcher.forceActiveFocus()
  }

  function editKeyboardLayouts() {
    if (!root.bar) return
    root.bar.run("omarchy-launch-config-editor "
      + Util.shellQuote(root.keyboardConfigPath))
    root.close()
  }

  function editKeyboardShortcut() {
    root.close()
    Quickshell.execDetached([
      "omarchy-launch-terminal",
      "nvim",
      "+" + String(root.keyboardOptionsLine),
      "+normal! zz",
      root.keyboardConfigPath
    ])
  }

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
    if (!optionsProcess.running) optionsProcess.running = true
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
    var itemCount = root.layouts.length + 1
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    root.cursorIndex = (root.cursorIndex + delta + itemCount) % itemCount
  }

  function activateCursor() {
    if (!root.cursorActive) return
    if (root.cursorIndex === root.layouts.length) root.openSettings()
    else root.selectLayout(root.cursorIndex)
  }

  onOpenedChanged: {
    if (!opened) return
    root.settingsPage = false
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

  Process {
    id: optionsProcess
    command: ["hyprctl", "-j", "getoption", "input:kb_options"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateKeyboardOptions(text)
    }
  }

  FileView {
    path: "/usr/share/X11/xkb/rules/evdev.lst"
    printErrors: false
    onLoaded: root.xkbOptionDescriptions = text()
  }

  FileView {
    path: root.keyboardConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.updateKeyboardConfig(text())
    onFileChanged: reload()
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
    color: pulseAnimation.running ? root.pulseColor : button.foreground
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
    contentWidth: panel.fittedContentWidth(Style.space(
      root.settingsPage ? 260 : 180))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsPage
        && root.customColorEditorVisible
        && customColorField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (!root.settingsPage) root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.settingsPage) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(6)

        Column {
          id: layoutColumn
          visible: !root.settingsPage
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

          PanelSeparator { foreground: root.bar.foreground }

          Button {
            width: layoutColumn.width
            text: "Settings"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            hasCursor: root.cursorActive
              && root.cursorIndex === root.layouts.length
            onClicked: root.openSettings()
            onHovered: function(hovered) {
              if (!hovered) return
              root.cursorActive = true
              root.cursorIndex = root.layouts.length
            }
          }
        }

        Column {
          id: settingsColumn
          visible: root.settingsPage
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "Pulse color"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Column {
            id: colorPresetColumn
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.colorPresets

              Button {
                id: presetButton
                required property var modelData
                width: colorPresetColumn.width
                text: String(modelData.label)
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                leftAlign: true
                rightPadding: horizontalPadding + Style.space(20)
                bordered: true
                focusable: true
                selected: !root.customColorEditorVisible
                  && root.pulseColor === String(modelData.value)
                onClicked: root.selectPresetColor(String(modelData.value))

                Rectangle {
                  width: Style.space(12)
                  height: width
                  radius: width / 2
                  anchors.right: parent.right
                  anchors.rightMargin: presetButton.horizontalPadding
                  anchors.verticalCenter: parent.verticalCenter
                  color: String(presetButton.modelData.value)
                  border.width: 1
                  border.color: Qt.rgba(
                    presetButton.foreground.r,
                    presetButton.foreground.g,
                    presetButton.foreground.b,
                    0.35)
                }
              }
            }

            Button {
              id: customColorButton
              width: colorPresetColumn.width
              text: "Custom"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              leftAlign: true
              rightPadding: horizontalPadding + Style.space(20)
              bordered: true
              focusable: true
              selected: root.customColorEditorVisible
                || root.presetForColor(root.pulseColor) === "custom"
              onClicked: root.openCustomColorEditor()

              Rectangle {
                width: Style.space(12)
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.rightMargin: customColorButton.horizontalPadding
                anchors.verticalCenter: parent.verticalCenter
                color: root.isPulseColor(customColorField.text)
                  ? root.normalizedPulseColor(customColorField.text)
                  : root.pulseColor
                border.width: 1
                border.color: Qt.rgba(
                  customColorButton.foreground.r,
                  customColorButton.foreground.g,
                  customColorButton.foreground.b,
                  0.35)
              }
            }
          }

          Row {
            visible: root.customColorEditorVisible
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: customColorField
              width: parent.width - applyColorButton.width - parent.spacing
              placeholderText: "#RRGGBB"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              validator: RegularExpressionValidator {
                regularExpression: /^#[0-9a-fA-F]{6}$/
              }
              onAccepted: root.applyPulseColor(text)
              Keys.onEscapePressed: root.closeSettings()
            }

            Button {
              id: applyColorButton
              text: "Apply"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              focusable: true
              enabled: customColorField.acceptableInput
              onClicked: root.applyPulseColor(customColorField.text)
            }
          }

          Text {
            visible: root.customColorEditorVisible
              && customColorField.text !== ""
              && !customColorField.acceptableInput
            width: parent.width
            text: "Use #RRGGBB, for example #2aa198."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "Layout shortcut"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(
              shortcutText.implicitHeight,
              editShortcutButton.implicitHeight)

            Text {
              id: shortcutText
              anchors.left: parent.left
              anchors.right: editShortcutButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: root.shortcutDescription
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            PanelActionButton {
              id: editShortcutButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒓"
              tooltipText: "Edit layout shortcut"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              size: Style.space(24)
              bordered: true
              focusable: true
              onClicked: root.editKeyboardShortcut()
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Button {
            width: parent.width
            text: "Edit keyboard layouts"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            focusable: true
            onClicked: root.editKeyboardLayouts()
          }

          PanelSeparator { foreground: root.bar.foreground }

          Button {
            id: backButton
            width: parent.width
            text: "Back"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            focusable: true
            onClicked: root.closeSettings()

            Text {
              anchors.right: parent.right
              anchors.rightMargin: backButton.horizontalPadding
              anchors.verticalCenter: parent.verticalCenter
              text: "󰅁"
              color: backButton.foreground
              font.family: backButton.fontFamily
              font.pixelSize: backButton.iconSize
            }
          }
        }
      }
    }
  }
}
