import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  readonly property string pluginPath:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.ilyazar.keyboard-layout"
  readonly property string trackerPath: pluginPath + "/native/keyboard-layoutd"

  property bool trackingEnabled: false
  property bool latinEnabled: false
  property bool overlayHeld: false
  property bool supportKnown: false
  property bool supported: false

  signal restoreRequested(int layout)
  signal trackerReady

  function setTrackingEnabled(enabled) {
    root.trackingEnabled = enabled === true
    root.syncTracker()
  }

  function setLatinEnabled(enabled) {
    var next = enabled === true
    if (root.latinEnabled === next) {
      root.syncTracker()
      return
    }
    root.latinEnabled = next
    if (layoutTracker.running) {
      trackerRestartTimer.stop()
      layoutTracker.running = false
    }
    root.syncTracker()
  }

  function setOverlayHeld(held) {
    root.overlayHeld = held === true
    root.writeOverlay()
  }

  function trackerCommand() {
    var command = ["setpriv", "--pdeathsig", "TERM", root.trackerPath]
    if (root.latinEnabled) command.push("--latin")
    return command
  }

  function syncTracker() {
    if (root.trackingEnabled && root.supported) {
      layoutTracker.command = root.trackerCommand()
      if (!layoutTracker.running) layoutTracker.running = true
      return
    }

    trackerRestartTimer.stop()
    if (layoutTracker.running) layoutTracker.running = false
  }

  function writeOverlay() {
    if (!layoutTracker.running || !root.latinEnabled) return
    layoutTracker.write(root.overlayHeld ? "latin-on\n" : "latin-off\n")
  }

  function updateSupport(raw) {
    root.supportKnown = true
    root.supported = String(raw || "").trim() === "x86_64"
    root.syncTracker()
  }

  function parseTrackerLine(line) {
    var text = String(line || "").trim()
    if (text === "ready") {
      root.trackerReady()
      root.writeOverlay()
      return
    }
    var match = text.match(/^restore:([0-9]+)$/)
    if (match) root.restoreRequested(Number(match[1]))
  }

  Component.onCompleted: architectureProcess.running = true

  Process {
    id: architectureProcess
    command: ["uname", "-m"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateSupport(text)
    }
  }

  Process {
    id: layoutTracker
    command: root.trackerCommand()
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.parseTrackerLine(line) }
    }
    onStarted: root.writeOverlay()
    onRunningChanged: {
      if (!running && root.trackingEnabled && root.supported)
        trackerRestartTimer.restart()
    }
  }

  Timer {
    id: trackerRestartTimer
    interval: 1000
    onTriggered: root.syncTracker()
  }
}
