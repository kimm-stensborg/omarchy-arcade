import Quickshell
import Quickshell.Io
import QtQuick
import "Library.js" as Library
import "Browse.js" as Browse
import "Pad.js" as Pad

// The stick: the controller RetroArch gives player 1, followed for as long as
// the shell runs. Home opens the arcade (closing the game first), and while
// the panel is up every press is read the way RetroArch reads it and turned
// into what it does on the wall or in the settings -- or, during the
// controller test, lit up on the board. The panel is handed in as `arcade`.
Item {
  id: stick
  property var arcade
  visible: false

  // What `arcade-launcher --controller` said: the controller RetroArch will
  // give player 1, the profile it matches, and which button does what.
  property var controllerParsed: Pad.parseController("")
  // The live test: presses read straight off the device, numbered the way
  // RetroArch numbers them and looked up in the same profile.
  property bool padTesting: false
  property var padState: ({ held: ({}), last: null, presses: 0 })
  // Which view the stick is driving, and whether it was the last thing used:
  // the footer then speaks stick rather than keyboard.
  readonly property string view: arcade.settingsOpen ? "settings" : (arcade.hasProblem ? "problem" : "wall")
  property bool stickLast: false

  // While the panel is up it has the stick to itself, so a game running
  // behind it does not also take every press.
  Connections {
    target: stick.arcade
    function onOpenedChanged() {
      if (stickProc.running) stickProc.write(stick.arcade.opened ? "grab\n" : "release\n")
      if (!stick.arcade.opened) stick.stickLast = false
    }
  }
  Component.onCompleted: {
    controllerProc.running = true
    stickProc.running = true
  }

  // What the controller is now, asked again: the settings do on every open.
  function readController() {
    if (!controllerProc.running) controllerProc.running = true
  }

  function startTest() {
    var pad = stick.controllerParsed.pad
    if (!pad) { arcade.settingsError = "no controller connected"; return }
    arcade.cancelEdit()
    stick.stopRepeat()
    stick.padState = ({ held: ({}), last: null, presses: 0 })
    stick.padTesting = true
  }

  function stopTest() {
    testExitTimer.stop()
    stick.padTesting = false
  }

  // One line from the stick listener. The listener runs for as long as the
  // shell does -- the plugin stays loaded -- so the stick can open the panel
  // as well as work it.
  function line(text) {
    if (text.indexOf("device\t") === 0 || text === "gone") {
      // Plugged in or out: what the panel knows about it is stale either way.
      stick.stopRepeat()
      if (!controllerProc.running) controllerProc.running = true
      if (arcade.opened && text !== "gone") stickProc.write("grab\n")
      if (text === "gone" && stick.padTesting) stick.stopTest()
      return
    }

    var press = Pad.padPress(stick.controllerParsed, text)
    if (!press) return
    if (arcade.opened && press.down && !stick.padTesting && arcade.wake()) return

    if (stick.padTesting) {
      var next = Pad.padEvent(stick.padState, stick.controllerParsed, text)
      if (next) stick.padState = next
      // Home is being tested like any button, so a tap only shows what it
      // does; held, it ends the test.
      if (press.retropad === "menu_toggle") {
        if (press.down) testExitTimer.restart()
        else testExitTimer.stop()
      }
      return
    }

    if (!arcade.opened) {
      // Home is the way back to the arcade: out of the game if one is
      // running, then the wall, ready for the next pick.
      if (press.down && press.retropad === "menu_toggle" && !homeProc.running) homeProc.running = true
      return
    }

    var action = Pad.stickAction(press.retropad, stick.view)
    if (!action) return
    if (!press.down) {
      if (stickRepeat.action === action) stick.stopRepeat()
      return
    }
    stick.stickLast = true
    stick.act(action)
    if (Pad.stickRepeats(action)) {
      stickRepeat.action = action
      stickRepeat.interval = 380
      stickRepeat.restart()
    }
  }

  function stopRepeat() {
    stickRepeat.stop()
    stickRepeat.action = ""
  }

  function act(action) {
    var view = stick.view
    // Half-typed text belongs to the keyboard; the stick can only let go of it.
    if (arcade.editing || arcade.capturing) {
      if (action === "back" || action === "close") arcade.cancelEdit()
      return
    }
    if (action === "close") { arcade.close(); return }
    if (view === "settings") {
      var row = arcade.settingsRow
      if (action === "up") arcade.moveSetting(-1)
      else if (action === "down") arcade.moveSetting(1)
      else if (action === "left") arcade.stepSetting(-1)
      else if (action === "right") arcade.stepSetting(1)
      else if (action === "back") arcade.closeSettings()
      else if (action === "activate" && row) {
        if (row.kind === "choice") arcade.stepSetting(1)
        else if (row.kind === "padtest") stick.startTest()
        else if (row.kind === "image") arcade.pickImage()
        else if (row.kind === "check") arcade.startCheck()
      }
      return
    }
    if (action === "settings") { arcade.openSettings(); return }
    if (action === "recheck") { arcade.refresh(); return }
    if (action === "back") {
      if (arcade.filterText) arcade.setFilter("")
      else if (Browse.filtersActive(arcade.filters)) arcade.clearFilters()
      else arcade.close()
      return
    }
    if (action === "play") { arcade.activate(); return }
    if (action === "favourite") { arcade.toggleFavourite(); return }
    if (action === "sort") { arcade.stepSort(1); return }
    if (action === "show") { arcade.stepFilter("show", 1); return }
    if (["left", "right", "up", "down", "page-up", "page-down"].indexOf(action) >= 0) arcade.move(action)
    else if ((action === "version-prev" || action === "version-next")
             && arcade.selected && Library.versionCount(arcade.selected) > 1)
      arcade.pickedVersions = Library.stepVersion(arcade.pickedVersions, arcade.selected,
                                                  action === "version-prev" ? -1 : 1)
  }

  Process {
    id: controllerProc
    command: [arcade.launcher, "--controller"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: stick.controllerParsed = Pad.parseController(text)
    }
  }

  // The stick, followed through unplugging and replugging for as long as the
  // shell runs. "grab" and "release" go the other way, on its stdin.
  Process {
    id: stickProc
    command: [arcade.launcher, "--controller", "--follow"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(text) { stick.line(text) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) console.warn(arcade.pluginId + ":", text.trim())
    }
    onRunningChanged: if (running && arcade.opened) Qt.callLater(function() { stickProc.write("grab\n") })
    // It only ends if something went wrong; try again shortly rather than
    // leave the stick dead until the shell restarts.
    onExited: stickRestart.restart()
  }

  Timer {
    id: stickRestart
    interval: 3000
    onTriggered: stickProc.running = true
  }

  // Home with the panel shut: close the game the launcher started, if any,
  // then open the panel. 72 means a RetroArch started some other way is
  // running; that one is not ours to close, so the panel stays shut.
  Process {
    id: homeProc
    command: [arcade.launcher, "--stop"]
    onExited: function(exitCode) {
      if ((exitCode === 0 || exitCode === 1) && !arcade.opened) arcade.open("{}")
    }
  }

  // A held lever keeps moving: a pause, then a steady step.
  Timer {
    id: stickRepeat
    property string action: ""
    interval: 380
    repeat: true
    onTriggered: {
      stickRepeat.interval = 90
      if (stickRepeat.action) stick.act(stickRepeat.action)
    }
  }

  // Home held for most of a second ends the controller test.
  Timer {
    id: testExitTimer
    interval: 900
    onTriggered: stick.stopTest()
  }
}
