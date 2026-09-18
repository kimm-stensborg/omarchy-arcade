import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Arcade launcher. A wall of title screens, one per ROM, with a line to type
// in above it; Enter boots the selection into RetroArch. The panel knows
// nothing about ROMs or cores: bin/arcade-launcher lists and launches,
// bin/arcade-artwork fetches the art, and when the launcher finds something
// missing its report is shown here in place of the wall.
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.kimm-stensborg.arcade"
  // The registry hands every plugin its own source directory, so the scripts
  // are found wherever the plugin was installed rather than at a path
  // hardcoded from the id.
  readonly property string pluginDir: root.manifest && root.manifest.__sourceDir
    ? String(root.manifest.__sourceDir)
    : Quickshell.env("HOME") + "/.config/omarchy/plugins/" + root.pluginId
  readonly property string launcher: root.pluginDir + "/bin/arcade-launcher"
  readonly property string artworkTool: root.pluginDir + "/bin/arcade-artwork"
  readonly property string home: Quickshell.env("HOME")

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property var games: []
  property bool loaded: false
  property bool loading: false
  // rom -> image path, or "" for a game the thumbnail server has nothing for.
  // Filled in as arcade-artwork reports, so tiles dress themselves while the
  // grid is already on screen.
  property var artMap: ({})
  // What the launcher said when it could not produce a list: no core, no ROMs,
  // no RetroArch. Shown in place of the wall, because an empty panel would be
  // a worse lie than the problem itself.
  property string problemReport: ""
  property string statusMessage: ""

  // ---- adding games by dropping them on the panel
  property bool dropHover: false
  // The line under the status after a drop: why something was turned away.
  property string addNote: ""
  property bool addOk: true
  // The first game a drop added, to be selected once the list has it.
  property string pendingSelectRom: ""
  // Everything --add has said so far, summed up when it finishes.
  property string addOutput: ""

  // ---- settings
  // Everything the panel can be told is a key in arcade.conf, read back from
  // the launcher rather than kept here: the file a person edits by hand and
  // the editor in this panel are the same setting, never two.
  property var settingsParsed: ({ configFile: "", configPresent: false, values: ({}) })
  property bool settingsOpen: false
  property int settingsIndex: 0
  // The row being typed into, or -1. Editing is a buffer rather than a real
  // text field because the panel owns the keyboard exclusively while it is up.
  property int editingIndex: -1
  property string editText: ""
  property string settingsError: ""
  // Values taken but not yet in the file; see Model.withPending.
  property var pendingSettings: ({})
  // The cabinet binds, from the arcade-only RetroArch profile.
  property var controlsParsed: ({ file: "", present: false, preset: "custom", values: ({}) })
  // The row waiting for a key to be pressed at it, or -1.
  property int capturingIndex: -1

  // Typing searches the whole library; with nothing typed, the games you last
  // played lead the wall -- at most one row of them, so Enter on open replays
  // the last game and the alphabet starts right below.
  readonly property int recentLimit: Math.min(root.columns,
    Math.max(0, Model.settingNumber(root.settingsParsed, "RECENT_GAMES", 6)))
  // Each game once, however many regional versions of it are in the ROM
  // directory; Tab steps through them. A search shows every version, since
  // "sfiiij" is typed by someone who wants that one.
  readonly property bool groupVersions: String((root.settingsParsed.values.GROUP_VERSIONS || {}).value || "on") !== "off"
  // group -> path of the version Tab last picked, for this open of the panel.
  property var pickedVersions: ({})
  readonly property bool searching: root.filterText.trim().length > 0
  readonly property var wallSource: root.groupVersions ? Model.groupGames(root.games, root.pickedVersions) : root.games
  readonly property var rows: root.searching
    ? Model.filterGames(root.games, root.filterText)
    : Model.wallGames(root.wallSource, root.recentLimit)
  // The first this many rows sit on the "continue playing" shelf.
  readonly property int shelfCount: root.searching ? 0 : Model.recentCount(root.wallSource, root.recentLimit)
  // The selected game's title screen, blurred behind everything. It follows
  // the selection a beat late, so holding the lever does not decode a
  // picture for every tile it passes.
  property string backdrop: ""
  // The game RetroArch is running right now, if the launcher started one.
  readonly property var playing: Model.playingGame(root.games)
  // Seconds since the epoch as of this open, for "2 hours ago". Taken once:
  // a label that ticks while you look at it is noise.
  property real now: Date.now() / 1000
  readonly property var selected: root.selectedIndex >= 0 && root.selectedIndex < root.rows.length
    ? root.rows[root.selectedIndex]
    : null
  readonly property bool hasProblem: root.problemReport.length > 0
  // The wall's own foot: the selected game's name, its facts, and keycaps.
  // The settings, the stick test and a setup problem keep the plain footer.
  readonly property bool infoBarShown: !root.settingsOpen && !root.padTesting && !root.hasProblem
    && root.rows.length > 0
  // Said in the footer before Enter is pressed, when a game is already running.
  readonly property string launchNote: Model.launchNote(root.selected, root.playing)

  // Theme: shares the [menu] surface tokens, so a theme that styles the
  // Omarchy menu styles this panel too.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property color accent: Color.accent
  readonly property color tileSurface: Util.alpha(root.foreground, 0.06)
  readonly property color tileBorder: Util.alpha(root.foreground, 0.10)
  // Arcade art is a CRT picture: it wants a black surround in any theme, the
  // way a cabinet bezel does.
  readonly property color artWell: "#07070b"
  // Slightly see-through, so the selected game's glow reaches the panel.
  readonly property color cardColor: Util.alpha(root.background, 0.9)
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.menuFamily
  // The panel is mostly artwork, so it gets room to breathe: a tight margin
  // makes a wall of screenshots look like a contact sheet.
  readonly property int contentMargin: Math.max(Style.spacing.panelPadding, Style.space(20))
  readonly property int contentSpacing: Math.max(Style.spacing.md, Style.space(14))
  readonly property int headerHeight: Math.max(Style.space(44), Style.font.title + Style.spacing.controlPaddingY * 2)
  readonly property int footerHeight: Math.max(Style.space(76), Math.round(Style.font.title * 1.5) + Style.font.caption + Style.space(26))

  // One editor, two files: arcade.conf decides what the panel does, the arcade
  // RetroArch profile decides what the cabinet's buttons do.
  readonly property var settingsRows: Model.withPending(Model.settingsRows(root.settingsParsed), root.pendingSettings)
    .concat(Model.controllerRows(root.controllerParsed))
    .concat(Model.controlRows(root.controlsParsed))

  // ---- the stick
  // What `arcade-launcher --controller` said: the controller RetroArch will
  // give player 1, the profile it matches, and which button does what.
  property var controllerParsed: Model.parseController("")
  // The live test: presses read straight off the device, numbered the way
  // RetroArch numbers them and looked up in the same profile.
  property bool padTesting: false
  // Which view the stick is driving, and whether it was the last thing used:
  // the footer then speaks stick rather than keyboard.
  readonly property string stickView: root.settingsOpen ? "settings" : (root.hasProblem ? "problem" : "wall")
  property bool stickLast: false
  // While the panel is up it has the stick to itself, so a game running
  // behind it does not also take every press.
  onOpenedChanged: {
    if (stickProc.running) stickProc.write(root.opened ? "grab\n" : "release\n")
    if (!root.opened) root.stickLast = false
  }
  Component.onCompleted: {
    controllerProc.running = true
    stickProc.running = true
  }
  property var padState: ({ held: ({}), last: null, presses: 0 })
  readonly property var settingsRow: root.settingsIndex >= 0 && root.settingsIndex < root.settingsRows.length
    ? root.settingsRows[root.settingsIndex]
    : null
  readonly property bool editing: root.editingIndex >= 0
  readonly property bool capturing: root.capturingIndex >= 0

  readonly property int tileSpacing: Style.space(16)
  // Title screens want room. TILE_SIZE is the width a tile aims for and
  // MAX_COLUMNS the most that go in a row, both from arcade.conf: the defaults
  // give a wide monitor bigger art rather than more of it.
  readonly property int targetTileWidth: Math.max(Style.space(Model.settingNumber(root.settingsParsed, "TILE_SIZE", 300)), 140)
  readonly property int cardWidth: Math.min(panel.width - Style.gapsOut * 2,
    Math.max(Style.space(1180), Math.round(panel.width * 0.72)))
  readonly property int cardHeight: Math.min(panel.height - Style.gapsOut * 2,
    Math.max(Style.space(760), Math.round(panel.height * 0.78)))
  readonly property int columns: Model.columnsFor(grid.width, root.targetTileWidth, root.tileSpacing,
    Model.settingNumber(root.settingsParsed, "MAX_COLUMNS", 6))
  readonly property int cellWidth: root.columns > 0 ? Math.floor(grid.width / root.columns) : root.targetTileWidth
  // 4:3 for the art, plus two lines of label underneath. Arcade screens are
  // that shape, so anything else would letterbox every tile.
  readonly property int cellHeight: Math.round((root.cellWidth - root.tileSpacing) * 0.75)
    + Style.font.body + Style.font.caption + Style.space(22) + root.tileSpacing

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.opened = true
    root.now = Date.now() / 1000
    root.pickedVersions = ({})
    root.filterText = payload.filter ? String(payload.filter) : ""
    root.selectedIndex = 0
    root.statusMessage = ""
    root.addNote = ""
    root.closeSettings()
    root.loadSettings()
    root.refresh()

    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.stopPadTest()
    root.stopStickRepeat()
    root.flushSettings()
    root.opened = false
  }

  // The library is re-read on every open: ROMs get added between sessions, and
  // a stale list would offer a game that is no longer there.
  function refresh() {
    if (listProc.running) return "busy"
    root.loading = true
    listProc.running = true
    return "ok"
  }

  function ping() { return "ok" }

  // ---------------------------------------------------------------- artwork

  // Ask about what is on screen first, then the rest of the library. Cached
  // images come back in the same breath as the request, so a second open is
  // dressed before it is drawn.
  function requestArt() {
    if (artProc.running || root.games.length === 0) return
    var wanted = Model.artWanted(root.artMap, root.rows, 24)
    if (wanted.length === 0) wanted = Model.artWanted(root.artMap, root.games, 24)
    if (wanted.length === 0) return
    artProc.command = [root.artworkTool].concat(wanted)
    artProc.running = true
  }

  onGamesChanged: root.requestArt()
  onRowsChanged: root.requestArt()

  // --------------------------------------------------------------- settings

  // Read on every open, because the tile size and the column cap are settings
  // too: the wall has to be laid out the way the config file says before it is
  // drawn, not after.
  function loadSettings() {
    if (!settingsProc.running) settingsProc.running = true
    if (!controllerProc.running) controllerProc.running = true
    if (!controlsProc.running) controlsProc.running = true
  }

  function openSettings() {
    root.settingsOpen = true
    root.settingsError = ""
    root.editingIndex = -1
    root.loadSettings()
  }

  function startPadTest() {
    var pad = root.controllerParsed.pad
    if (!pad) { root.settingsError = "no controller connected"; return }
    root.cancelEdit()
    root.stopStickRepeat()
    root.padState = ({ held: ({}), last: null, presses: 0 })
    root.padTesting = true
  }

  function stopPadTest() {
    testExitTimer.stop()
    root.padTesting = false
  }

  // ------------------------------------------------------------ the stick

  // One line from the stick listener. The listener runs for as long as the
  // shell does -- the plugin stays loaded -- so the stick can open the panel
  // as well as work it.
  function stickLine(line) {
    if (line.indexOf("device\t") === 0 || line === "gone") {
      // Plugged in or out: what the panel knows about it is stale either way.
      root.stopStickRepeat()
      if (!controllerProc.running) controllerProc.running = true
      if (root.opened && line !== "gone") stickProc.write("grab\n")
      if (line === "gone" && root.padTesting) root.stopPadTest()
      return
    }

    var press = Model.padPress(root.controllerParsed, line)
    if (!press) return

    if (root.padTesting) {
      var next = Model.padEvent(root.padState, root.controllerParsed, line)
      if (next) root.padState = next
      // Home is being tested like any button, so a tap only shows what it
      // does; held, it ends the test.
      if (press.retropad === "menu_toggle") {
        if (press.down) testExitTimer.restart()
        else testExitTimer.stop()
      }
      return
    }

    if (!root.opened) {
      // Home is the way back to the arcade: out of the game if one is
      // running, then the wall, ready for the next pick.
      if (press.down && press.retropad === "menu_toggle" && !homeProc.running) homeProc.running = true
      return
    }

    var action = Model.stickAction(press.retropad, root.stickView)
    if (!action) return
    if (!press.down) {
      if (stickRepeat.action === action) root.stopStickRepeat()
      return
    }
    root.stickLast = true
    root.stickAction(action)
    if (Model.stickRepeats(action)) {
      stickRepeat.action = action
      stickRepeat.interval = 380
      stickRepeat.restart()
    }
  }

  function stopStickRepeat() {
    stickRepeat.stop()
    stickRepeat.action = ""
  }

  function stickAction(action) {
    var view = root.stickView
    // Half-typed text belongs to the keyboard; the stick can only let go of it.
    if (root.editing || root.capturing) {
      if (action === "back" || action === "close") root.cancelEdit()
      return
    }
    if (action === "close") { root.close(); return }
    if (view === "settings") {
      var row = root.settingsRow
      if (action === "up") root.moveSetting(-1)
      else if (action === "down") root.moveSetting(1)
      else if (action === "left") root.stepSetting(-1)
      else if (action === "right") root.stepSetting(1)
      else if (action === "back") root.closeSettings()
      else if (action === "activate" && row) {
        if (row.kind === "choice") root.stepSetting(1)
        else if (row.kind === "padtest") root.startPadTest()
      }
      return
    }
    if (action === "settings") { root.openSettings(); return }
    if (action === "recheck") { root.refresh(); return }
    if (action === "back") {
      if (root.filterText) root.setFilter("")
      else root.close()
      return
    }
    if (action === "play") { root.activate(); return }
    if (["left", "right", "up", "down", "page-up", "page-down"].indexOf(action) >= 0) root.move(action)
    else if ((action === "version-prev" || action === "version-next")
             && root.selected && Model.versionCount(root.selected) > 1)
      root.pickedVersions = Model.stepVersion(root.pickedVersions, root.selected,
                                              action === "version-prev" ? -1 : 1)
  }

  function closeSettings() {
    root.stopPadTest()
    root.flushSettings()
    root.settingsOpen = false
    root.editingIndex = -1
    root.settingsError = ""
  }

  function moveSetting(delta) {
    if (root.settingsRows.length === 0) return
    root.cancelEdit()
    root.settingsIndex = Model.wrapIndex(root.settingsIndex, delta, root.settingsRows.length)
    Qt.callLater(function() { settingsList.positionViewAtIndex(root.settingsIndex, ListView.Contain) })
  }

  function beginEdit(seed) {
    var row = root.settingsRow
    if (!row || row.kind === "choice" || row.kind === "padinfo") return
    if (row.kind === "bind") { root.beginCapture(); return }
    if (row.kind === "padtest") { root.startPadTest(); return }
    root.editingIndex = root.settingsIndex
    root.editText = seed === undefined ? row.value : seed
    root.settingsError = ""
  }

  function cancelEdit() {
    root.editingIndex = -1
    root.editText = ""
    root.capturingIndex = -1
    root.settingsError = ""
  }

  // Binding is done by pressing the key, the way RetroArch and every arcade
  // front end do it: there is no spelling of "right shift" worth typing.
  function beginCapture() {
    var row = root.settingsRow
    if (!row || row.kind !== "bind") return
    root.editingIndex = -1
    root.capturingIndex = root.settingsIndex
    root.settingsError = ""
  }

  // Esc is how you get out of capture, so it can never be captured -- which is
  // also why it stays RetroArch's own way out of a game.
  function captureKey(event) {
    var row = root.settingsRow
    if (!row) { root.cancelEdit(); return }

    var name = Model.retroarchKey(event.key, event.modifiers, event.text)
    if (!name) {
      root.settingsError = "RetroArch has no name for that key"
      return
    }
    root.capturingIndex = -1
    root.applyControl(row, name)
  }

  function commitEdit() {
    var row = root.settingsRow
    if (!row) return
    root.applySetting(row, root.editText)
  }

  // One write, one re-read. The launcher owns the file format, so the panel
  // never edits arcade.conf itself -- it asks for a key to be set and then
  // asks what the file says now, which is also how a hand edit made while the
  // panel was open shows up.
  function applySetting(row, value) {
    if (row && (row.kind === "bind" || row.layout)) {
      root.cancelEdit()
      root.applyControl(row, value)
      return
    }

    var problem = Model.validateSetting(row, value)
    if (problem) {
      root.settingsError = problem
      return
    }

    var next = Model.normalizeSetting(row, value)
    root.cancelEdit()
    if (next === row.value) return

    var pending = ({})
    for (var key in root.pendingSettings) pending[key] = root.pendingSettings[key]
    pending[row.key] = next
    root.pendingSettings = pending
    writeTimer.restart()
  }

  // A control is one write to the arcade profile: a layout replaces the lot,
  // a bind replaces one line, and an empty bind removes it so whatever the
  // RetroArch config says takes over again.
  function applyControl(row, value) {
    if (controlProc.running) {
      root.settingsError = "still writing the last change"
      return
    }
    root.settingsError = ""
    controlProc.command = row.layout
      ? [root.launcher, "--controls-preset", String(value)]
      : [root.launcher, "--set-control", row.id + "=" + String(value)]
    controlProc.running = true
  }

  // Everything waiting, in one --set. A held arrow key steps the row far
  // faster than a process can be started for each press; the row moves at the
  // speed of the key and the file catches up when it stops.
  function flushSettings() {
    writeTimer.stop()
    var args = Model.pendingArgs(root.pendingSettings)
    if (args.length === 0) return
    if (setProc.running) { writeTimer.restart(); return }

    setProc.changedKeys = Object.keys(root.pendingSettings)
    setProc.command = [root.launcher, "--set"].concat(args)
    setProc.running = true
    root.pendingSettings = ({})
  }

  // Back to whatever the launcher decides on its own: the line is removed from
  // the config file rather than written with a default copied into it, so a
  // later change of default is picked up.
  function resetSetting() {
    var row = root.settingsRow
    if (!row || !Model.isOverridden(row)) return
    root.cancelEdit()

    // A control goes back to whatever RetroArch itself has bound; a layout row
    // has nothing to reset to, since some layout is always in force.
    if (row.layout) return
    if (row.kind === "bind") { root.applyControl(row, ""); return }

    var pending = ({})
    for (var key in root.pendingSettings) pending[key] = root.pendingSettings[key]
    pending[row.key] = ""
    root.pendingSettings = pending
    root.flushSettings()
  }

  function stepSetting(delta) {
    var row = root.settingsRow
    if (!row || root.editing) return
    if (row.kind === "choice") root.applySetting(row, Model.cycleOption(row.options, row.value, delta))
    else if (row.kind === "number") root.applySetting(row, Model.stepNumber(row, row.value, delta))
  }

  function isTypable(event) {
    return event.text && event.text.length === 1
      && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127
      && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
  }

  // Keys while the editor is up. Returns whether the key was ours, which is
  // every key once a row is being typed into: a stray arrow should not move
  // the cursor out from under a half-typed path.
  function settingsKey(event) {
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var row = root.settingsRow

    if (event.key === Qt.Key_Escape) {
      if (root.editing || root.capturing) root.cancelEdit()
      else root.closeSettings()
      return true
    }

    if (root.capturing) {
      root.captureKey(event)
      return true
    }

    if (root.editing) {
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.commitEdit(); return true }
      if (Util.editsFilter(event, root.editText)) { root.editText = Util.editedFilter(event, root.editText); return true }
      if (root.isTypable(event)) { root.editText += event.text; return true }
      return true
    }

    if (event.key === Qt.Key_F5) { root.loadSettings(); return true }
    if (ctrl && event.key === Qt.Key_Comma) { root.closeSettings(); return true }
    if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) { root.moveSetting(1); return true }
    if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) { root.moveSetting(-1); return true }
    if (event.key === Qt.Key_Home) { root.settingsIndex = 0; return true }
    if (event.key === Qt.Key_End) { root.settingsIndex = root.settingsRows.length - 1; return true }
    if (event.key === Qt.Key_Right) { root.stepSetting(1); return true }
    if (event.key === Qt.Key_Left) { root.stepSetting(-1); return true }
    if (event.key === Qt.Key_Delete) { root.resetSetting(); return true }

    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      if (row && row.kind === "choice") root.stepSetting(1)
      else root.beginEdit()
      return true
    }
    // Typing goes straight into the row rather than needing Enter first, and
    // appends rather than replaces: a path is usually being corrected, not
    // rewritten.
    if (row && ["choice", "bind", "padinfo", "padtest"].indexOf(row.kind) < 0) {
      if (event.key === Qt.Key_Backspace) { root.beginEdit(String(row.value).slice(0, -1)); return true }
      if (root.isTypable(event)) { root.beginEdit(String(row.value) + event.text); return true }
    }
    return false
  }

  // ------------------------------------------------------------- navigation

  // up, down, left, right, page-up, page-down -- across the shelf and the
  // wall as one; see Model.wallMove.
  function move(action) {
    if (root.rows.length === 0) return
    pointerGate.reset()
    if (!addProc.running) { root.statusMessage = ""; root.addNote = "" }
    root.setSelected(Model.wallMove(root.selectedIndex, action, root.columns, root.shelfCount, root.rows.length))
  }

  function setSelected(index) {
    root.selectedIndex = Model.clampIndex(index, root.rows.length)
    // The shelf never scrolls; only a game on the wall needs bringing into view.
    Qt.callLater(function() {
      if (root.selectedIndex >= root.shelfCount)
        grid.positionViewAtIndex(root.selectedIndex - root.shelfCount, GridView.Contain)
    })
  }

  // Romsets dropped on the panel: copied into the ROM directory, each one
  // test-loaded headless, kept only if it runs, artwork fetched. The launcher
  // does all of it; the panel says what happened and goes to the new game.
  // The file chooser, for adding romsets: + in the header, or Alt+A. The
  // panel hides while it is open -- it covers the screen and holds the
  // keyboard, so the chooser would otherwise open behind it -- and comes back
  // with the result, or as it was if the choosing was cancelled.
  function pickGames() {
    if (pickProc.running || addProc.running) return
    if (root.settingsOpen) root.closeSettings()
    root.stopStickRepeat()
    pickProc.running = true
  }

  function addGames(paths) {
    if (paths.length === 0) return
    if (addProc.running) { root.statusMessage = "Still checking the last drop…"; return }
    if (root.settingsOpen) root.closeSettings()
    root.addNote = ""
    root.statusMessage = paths.length === 1
      ? "Checking " + paths[0].replace(/^.*\//, "") + "…"
      : "Checking " + paths.length + " files…"
    root.addOutput = ""
    addProc.command = [root.launcher, "--add"].concat(paths)
    addProc.running = true
  }

  function setFilter(next) {
    root.addNote = ""
    root.filterText = next
    // Any edit re-aims at the best match rather than keeping a tile that the
    // new filter may have pushed somewhere else entirely.
    root.selectedIndex = 0
    pointerGate.reset()
    Qt.callLater(function() { grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  // ---------------------------------------------------------------- actions

  function launch(game) {
    if (!game) return
    launchProc.command = [root.launcher, game.path]
    launchProc.running = true
    root.statusMessage = (game.playing ? "Back to " : "Starting ") + game.title + "…"
    // Close immediately: RetroArch takes a second or two to appear, and a
    // panel sitting on top of a game that is about to go fullscreen is worse
    // than one that got out of the way.
    root.close()
  }

  function activate() {
    if (root.hasProblem) { root.refresh(); return }
    root.launch(root.selected)
  }

  // --------------------------------------------------------------- backends

  Process {
    id: listProc
    command: [root.launcher, "--list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.games = Model.parseList(text)
        root.loaded = true
        root.selectedIndex = 0
        if (root.pendingSelectRom) {
          var rom = root.pendingSelectRom
          root.pendingSelectRom = ""
          Qt.callLater(function() {
            for (var i = 0; i < root.rows.length; i++) {
              if (root.rows[i].rom === rom) { root.setSelected(i); break }
            }
          })
        }
      }
    }
    // --list reports problems on stderr: the same text `arcade-launcher
    // --doctor` prints, already written for a human to read.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.problemReport = text ? text.trim() : ""
    }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode === 0) root.problemReport = ""
      else if (root.problemReport.length === 0) root.problemReport = "arcade-launcher exited with code " + exitCode
    }
  }

  Process {
    id: artProc
    // Whether this run reported anything. A run that did not -- python
    // missing, an unusable ART_DIR -- would be asked the same question again
    // straight away, forever.
    property bool progressed: false
    onRunningChanged: if (running) progressed = false
    stdout: SplitParser {
      onRead: function(line) {
        var next = Model.withArt(root.artMap, line)
        if (next) {
          root.artMap = next
          artProc.progressed = true
        }
      }
    }
    // Why a tile stayed blank -- an unreachable thumbnail server, most often --
    // belongs in the shell log rather than nowhere.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) console.warn(root.pluginId + ":", text.trim())
    }
    // Keep going until every game has either an image or a recorded miss.
    onExited: function(exitCode) {
      if (exitCode === 0 && artProc.progressed) Qt.callLater(function() { root.requestArt() })
    }
  }

  Process {
    id: settingsProc
    command: [root.launcher, "--settings"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.settingsParsed = Model.parseSettings(text)
    }
  }

  Process {
    id: addProc
    // Line by line, so a big drop counts through in the info bar.
    stdout: SplitParser {
      onRead: function(line) {
        root.addOutput += line + "\n"
        var progress = Model.addProgress(line)
        if (progress) root.statusMessage = progress
      }
    }
    onRunningChanged: {
      if (running) return
      var summary = Model.addSummary(root.addOutput)
      root.statusMessage = summary.title
      if (!root.addNote) root.addNote = summary.detail
      root.addOk = root.addOk && summary.ok
      if (summary.added.length > 0) {
        root.filterText = ""
        root.pendingSelectRom = summary.added[0]
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) {
        root.addNote = text.trim().split("\n")[0]
        root.addOk = false
      }
    }
    onExited: root.refresh()
  }

  Process {
    id: pickProc
    command: [root.launcher, "--pick"]
    stdout: StdioCollector {
      id: pickOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: pickErr
      waitForEnd: true
    }
    onExited: function(exitCode) {
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      if (exitCode === 0) {
        root.addGames(pickOut.text.split("\n").filter(function(p) { return p.length > 0 }))
      } else if (pickErr.text && pickErr.text.trim()) {
        // No chooser to open: say so where the result would have gone.
        root.statusMessage = "Could not open a file chooser"
        root.addNote = pickErr.text.trim().split("\n")[0].replace(/^arcade-launcher: /, "")
        root.addOk = false
      }
    }
  }

  Process {
    id: controllerProc
    command: [root.launcher, "--controller"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controllerParsed = Model.parseController(text)
    }
  }

  // The stick, followed through unplugging and replugging for as long as the
  // shell runs. "grab" and "release" go the other way, on its stdin.
  Process {
    id: stickProc
    command: [root.launcher, "--controller", "--follow"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.stickLine(line) }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) console.warn(root.pluginId + ":", text.trim())
    }
    onRunningChanged: if (running && root.opened) Qt.callLater(function() { stickProc.write("grab\n") })
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
    command: [root.launcher, "--stop"]
    onExited: function(exitCode) {
      if ((exitCode === 0 || exitCode === 1) && !root.opened) root.open("{}")
    }
  }

  Timer {
    id: backdropTimer
    interval: 140
    onTriggered: root.backdrop = Model.artFor(root.artMap, root.selected)
  }
  onSelectedChanged: backdropTimer.restart()
  onArtMapChanged: if (!root.backdrop) backdropTimer.restart()

  // A held lever keeps moving: a pause, then a steady step.
  Timer {
    id: stickRepeat
    property string action: ""
    interval: 380
    repeat: true
    onTriggered: {
      stickRepeat.interval = 90
      if (stickRepeat.action) root.stickAction(stickRepeat.action)
    }
  }

  // Home held for most of a second ends the controller test.
  Timer {
    id: testExitTimer
    interval: 900
    onTriggered: root.stopPadTest()
  }

  Process {
    id: controlsProc
    command: [root.launcher, "--controls"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controlsParsed = Model.parseControls(text)
    }
  }

  Process {
    id: controlProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) root.settingsError = text.trim()
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (!root.settingsError) root.settingsError = "could not write the arcade profile"
        return
      }
      // The first write makes the profile and points RETROARCH_CONFIG at it,
      // so the settings above are as stale as the binds below.
      root.loadSettings()
    }
  }

  Process {
    id: setProc
    // Which keys this write was for, so the right part of the panel is thrown
    // away when it lands.
    property var changedKeys: []
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) root.settingsError = text.trim()
    }
    onExited: function(exitCode) {
      var keys = setProc.changedKeys
      setProc.changedKeys = []
      if (exitCode !== 0) {
        if (!root.settingsError) root.settingsError = "could not write the config file"
        return
      }

      root.loadSettings()
      var library = false, artwork = false
      for (var i = 0; i < keys.length; i++) {
        if (Model.affectsLibrary(keys[i])) library = true
        if (Model.affectsArtwork(keys[i])) artwork = true
      }
      // Artwork policy changed: forget what is known about every tile, or an
      // ARTWORK that just went back on would never ask for anything again.
      if (artwork) root.artMap = ({})
      if (library) root.refresh()
      else if (artwork) root.requestArt()
      if (Model.pendingArgs(root.pendingSettings).length) writeTimer.restart()
    }
  }

  Process {
    id: launchProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim().length > 0) console.warn(root.pluginId + ":", text.trim())
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  // ------------------------------------------------------------------ a tile
  //
  // One game: its title screen, its name, and a word about it when there is
  // one worth saying. The shelf and the wall both draw these; the Loader that
  // places one says which game it is.
  Component {
    id: gameTile

    Item {
      id: tile
      readonly property int index: parent ? parent.tileIndex : -1
      readonly property var entry: index >= 0 && index < root.rows.length ? root.rows[index] : null
      readonly property bool active: index === root.selectedIndex
      readonly property string art: Model.artFor(root.artMap, entry)
      readonly property bool pending: Model.artPending(root.artMap, entry)
      readonly property string note: Model.tileNote(entry, root.now)

      Item {
        anchors.fill: parent
        anchors.margins: Math.round(root.tileSpacing / 2)

        // The selected tile lifts out of the wall and glows, the way a lit
        // cabinet does in a dark arcade; the rest step back a little.
        scale: tile.active ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        RectangularShadow {
          anchors.fill: frame
          radius: frame.radius
          blur: Style.space(28)
          spread: Style.space(2)
          color: Util.alpha(root.accent, 0.55)
          opacity: tile.active ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 140 } }
        }

        Rectangle {
          id: frame
          anchors.fill: parent
          radius: root.cornerRadius
          color: tile.active ? Util.alpha(root.accent, 0.16) : root.tileSurface
          border.width: tile.active ? Math.max(2, Style.space(2)) : Math.max(1, Style.space(1))
          border.color: tile.active ? root.accent : root.tileBorder
          Behavior on color { ColorAnimation { duration: 140 } }
          Behavior on border.color { ColorAnimation { duration: 140 } }

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(6)
            spacing: Style.space(6)

            // ---- artwork
            Rectangle {
              id: well
              width: parent.width
              height: Math.round(width * 0.75)
              radius: Math.max(2, root.cornerRadius - Style.space(3))
              color: root.artWell
              clip: true

              Image {
                anchors.fill: parent
                anchors.margins: 1
                source: tile.art ? "file://" + tile.art : ""
                visible: tile.art.length > 0 && status === Image.Ready
                fillMode: Image.PreserveAspectFit
                // Arcade art is 224 lines tall. Smoothing it into a 200px
                // tile turns a title screen into a smear; nearest-neighbour
                // keeps the pixels it was drawn in.
                smooth: false
                mipmap: false
                asynchronous: true
                cache: true
                sourceSize.width: 640
                opacity: tile.active ? 1 : 0.8
                Behavior on opacity { NumberAnimation { duration: 140 } }
              }

              // The game on screen right now, marked on its own art so it is
              // found at a glance on a wall of title screens.
              Rectangle {
                visible: !!(tile.entry && tile.entry.playing)
                z: 2
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                height: Style.font.caption + Style.space(8)
                width: playingText.implicitWidth + Style.space(14)
                radius: height / 2
                color: root.accent

                Text {
                  id: playingText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "PLAYING"
                  color: root.artWell
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: Style.space(1)
                }
              }

              // No artwork, or none yet: the game's initials set like a
              // marquee, which beats an empty black rectangle.
              Text {
                anchors.centerIn: parent
                visible: tile.art.length === 0
                textFormat: Text.PlainText
                text: Model.initials(tile.entry ? tile.entry.title : "")
                color: Util.alpha(root.foreground, tile.pending ? 0.28 : 0.42)
                font.family: root.fontFamily
                font.pixelSize: Math.round(well.height * 0.34)
                font.letterSpacing: Style.space(2)
                font.bold: true

                SequentialAnimation on opacity {
                  running: tile.pending && root.opened
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutQuad }
                  NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                }
              }
            }

            // ---- the name, and a word about it
            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: tile.entry ? tile.entry.title : ""
              color: tile.active ? root.accent : root.foreground
              opacity: tile.active ? 1 : 0.88
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: tile.active
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: tile.note || " "
              color: tile.entry && tile.entry.playing ? root.accent : root.foreground
              opacity: tile.entry && tile.entry.playing ? 0.9 : 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: if (pointerGate.moved) root.setSelected(tile.index)
          onClicked: {
            root.setSelected(tile.index)
            root.activate()
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------- view

  PanelWindow {
    id: panel
    // Hidden, not closed, while the file chooser is open.
    visible: root.opened && !pickProc.running
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-arcade"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The selected game's title screen, blurred across the whole screen and
    // pushed well back: the room lit by the cabinet you are standing at.
    Image {
      id: backdropArt
      anchors.fill: parent
      source: root.backdrop ? "file://" + root.backdrop : ""
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: 320
      asynchronous: true
      retainWhileLoading: true
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: backdropArt
      autoPaddingEnabled: false
      blurEnabled: true
      blur: 1.0
      blurMax: 64
      saturation: 0.1
      brightness: -0.2
      opacity: backdropArt.status === Image.Ready && root.backdrop ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: 260 } }
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    // The scrim alone lets the desktop through; the arcade wants the room dark.
    Rectangle {
      anchors.fill: parent
      color: Util.alpha("#000000", 0.45)
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.cardColor
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        // BorderSurface exposes its padding as insets rather than applying it,
        // so the content inset is anchored here. Without this the wordmark sits
        // flush against the border.
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          root.stickLast = false
          // The test owns the keyboard while it runs: the stick is what is
          // being tested, and Esc is the way back.
          if (root.padTesting) {
            if (event.key === Qt.Key_Escape) root.stopPadTest()
            event.accepted = true
            return
          }
          if (root.settingsOpen) {
            event.accepted = root.settingsKey(event)
            return
          }
          if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Comma) {
            root.openSettings()
            event.accepted = true
            return
          }
          // Alt+A adds games: the file chooser.
          if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_A) {
            root.pickGames()
            event.accepted = true
            return
          }
          if (event.key === Qt.Key_Escape) {
            root.close()
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate()
            event.accepted = true
          } else if (event.key === Qt.Key_Right || (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier))) {
            root.move("right")
            event.accepted = true
          } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))) {
            root.move("left")
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.move("down")
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.move("up")
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.move("page-down")
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.move("page-up")
            event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            root.setSelected(0)
            event.accepted = true
          } else if (event.key === Qt.Key_End) {
            root.setSelected(root.rows.length - 1)
            event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            // Another version of the same game, in the same tile: the wall
            // does not move, only what Enter will start.
            if (root.selected && Model.versionCount(root.selected) > 1)
              root.pickedVersions = Model.stepVersion(root.pickedVersions, root.selected,
                                                      event.key === Qt.Key_Backtab ? -1 : 1)
            event.accepted = true
          } else if (event.key === Qt.Key_F5) {
            // The config file is as likely to have changed as the ROM
            // directory, and a hand edit should not need the panel reopened.
            root.loadSettings()
            root.refresh()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.text && event.text.length === 1
                     && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        Column {
          anchors.fill: parent
          spacing: root.contentSpacing

          // ------------------------------------------------------------ header
          Item {
            width: parent.width
            height: root.headerHeight

            Text {
              id: wordmark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.settingsOpen ? "SETTINGS" : "ARCADE"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.space(3)
            }

            // The search line is a field rather than loose text: it is the one
            // thing in the panel you are meant to type into, and it should look
            // like it before anything is typed.
            Rectangle {
              id: searchField
              visible: !root.settingsOpen
              anchors.left: wordmark.right
              anchors.leftMargin: Style.space(16)
              anchors.right: addButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              height: parent.height
              radius: height / 2
              color: Util.alpha(root.foreground, 0.06)
              border.width: Math.max(1, Style.space(1))
              border.color: root.filterText ? Util.alpha(root.accent, 0.45) : Util.alpha(root.foreground, 0.10)
              Behavior on border.color { ColorAnimation { duration: 130 } }

              Text {
                id: searchGlyph
                anchors.left: parent.left
                anchors.leftMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "󰍉"
                color: root.filterText ? root.accent : root.foreground
                opacity: root.filterText ? 0.9 : 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                id: searchLine
                textFormat: Text.PlainText
                anchors.left: searchGlyph.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter
                text: root.filterText || "Search games…"
                color: root.foreground
                opacity: root.filterText ? 1 : 0.42
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }

              // A caret, so an empty field still looks like something you type
              // in rather than a label.
              Rectangle {
                anchors.left: searchLine.left
                anchors.leftMargin: root.filterText ? Math.min(searchLine.contentWidth + Style.space(3), searchLine.width) : 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Style.space(2))
                height: Style.font.heading
                radius: width / 2
                color: root.accent
                opacity: caretBlink.on ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: 90 } }
              }
            }

            // Which file is being edited, in the search line's place: every row
            // below is a line in it, and a person who would rather edit it by
            // hand should be told where it is.
            Text {
              id: configPath
              visible: root.settingsOpen
              anchors.left: wordmark.right
              anchors.leftMargin: Style.space(16)
              anchors.right: gearButton.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: Model.shortenPath(root.settingsParsed.configFile, root.home)
                + (root.settingsParsed.configPresent ? "" : "  ·  not created yet")
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideMiddle
            }

            // Adding games: the file chooser. (Dropping files anywhere on the
            // panel works too.)
            Rectangle {
              id: addButton
              visible: !root.settingsOpen
              anchors.right: gearButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.height
              height: parent.height
              radius: height / 2
              color: addArea.containsMouse ? Util.alpha(root.accent, 0.16) : Util.alpha(root.foreground, 0.06)
              Behavior on color { ColorAnimation { duration: 130 } }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰐕"
                color: addArea.containsMouse ? root.accent : root.foreground
                opacity: addArea.containsMouse ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              MouseArea {
                id: addArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.pickGames()
              }
            }

            // The wall's way in and out of the editor, for the half of the time
            // a pointer is already in hand.
            Rectangle {
              id: gearButton
              anchors.right: countPill.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.height
              height: parent.height
              radius: height / 2
              color: gearArea.containsMouse || root.settingsOpen
                ? Util.alpha(root.accent, 0.16) : Util.alpha(root.foreground, 0.06)
              Behavior on color { ColorAnimation { duration: 130 } }

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.settingsOpen ? "󰅖" : "󰒓"
                color: root.settingsOpen || gearArea.containsMouse ? root.accent : root.foreground
                opacity: root.settingsOpen || gearArea.containsMouse ? 1 : 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              MouseArea {
                id: gearArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
              }
            }

            Rectangle {
              id: countPill
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              height: Style.font.caption + Style.space(12)
              width: countText.implicitWidth + Style.space(20)
              radius: height / 2
              color: root.hasProblem ? Util.alpha(root.accent, 0.18) : Util.alpha(root.foreground, 0.08)

              Text {
                id: countText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.settingsOpen ? "Esc goes back"
                  : (root.loading ? "reading library…"
                  : (root.hasProblem ? "setup needed" : (root.filterText.trim().length > 0
                  ? Model.describeCount(root.rows.length, root.games.length)
                  : Model.describeCount(root.rows.length, root.rows.length))))
                color: root.hasProblem && !root.settingsOpen ? root.accent : root.foreground
                opacity: root.hasProblem && !root.settingsOpen ? 1 : 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // -------------------------------------------------------------- body
          Item {
            width: parent.width
            height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2

            // The wall: games you played lately on a shelf of their own, then
            // the whole library below it. The shelf stays put while the
            // library scrolls, so "continue where I was" is always one move
            // up.
            Item {
              id: wall
              anchors.fill: parent
              visible: !root.settingsOpen && !root.hasProblem && root.rows.length > 0

              Text {
                id: shelfLabel
                visible: root.shelfCount > 0
                height: root.shelfCount > 0 ? Style.font.caption + Style.space(4) : 0
                textFormat: Text.PlainText
                text: "CONTINUE PLAYING"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: Style.space(2)
              }

              ListView {
                id: shelf
                anchors.top: shelfLabel.bottom
                anchors.topMargin: visible ? Style.space(6) : 0
                width: parent.width
                height: visible ? root.cellHeight : 0
                visible: root.shelfCount > 0
                orientation: ListView.Horizontal
                interactive: false
                model: root.shelfCount
                delegate: Loader {
                  required property int index
                  readonly property int tileIndex: index
                  width: root.cellWidth
                  height: root.cellHeight
                  z: tileIndex === root.selectedIndex ? 2 : 1
                  sourceComponent: gameTile
                }
              }

              Text {
                id: wallLabel
                anchors.top: shelf.bottom
                anchors.topMargin: visible ? Style.space(10) : 0
                visible: root.shelfCount > 0
                height: root.shelfCount > 0 ? Style.font.caption + Style.space(4) : 0
                textFormat: Text.PlainText
                text: "ALL GAMES"
                color: root.foreground
                opacity: 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: Style.space(2)
              }

              GridView {
                id: grid
                anchors.top: wallLabel.bottom
                anchors.topMargin: wallLabel.visible ? Style.space(6) : 0
                anchors.bottom: parent.bottom
                width: parent.width
                model: Math.max(0, root.rows.length - root.shelfCount)
                cellWidth: root.cellWidth
                cellHeight: root.cellHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: root.cellHeight * 3
                delegate: Loader {
                  required property int index
                  readonly property int tileIndex: index + root.shelfCount
                  width: grid.cellWidth
                  height: grid.cellHeight
                  z: tileIndex === root.selectedIndex ? 2 : 1
                  sourceComponent: gameTile
                }
              }

              // A slim indicator instead of a scrollbar: the wall scrolls with
              // the selection, so this is a hint about how much library is
              // left, not something to drag.
              Rectangle {
                visible: grid.contentHeight > grid.height
                width: Math.max(2, Style.space(3))
                radius: width / 2
                color: Util.alpha(root.foreground, 0.18)
                anchors.right: parent.right
                y: grid.y + grid.visibleArea.yPosition * grid.height
                height: Math.max(Style.space(24), grid.visibleArea.heightRatio * grid.height)
                Behavior on y { NumberAnimation { duration: 90 } }
              }

              // The wall fades out into the info bar rather than being sliced
              // off by it, which is the only cue that there is more below.
              Rectangle {
                visible: grid.contentHeight > grid.height
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Style.space(56)
                gradient: Gradient {
                  GradientStop { position: 0.0; color: "transparent" }
                  GradientStop { position: 1.0; color: root.cardColor }
                }
              }
            }

            // Nothing matched what was typed.
            Column {
              anchors.centerIn: parent
              visible: !root.settingsOpen && !root.hasProblem && root.loaded && root.rows.length === 0
              spacing: Style.space(6)

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.games.length === 0 ? "No ROMs found" : "Nothing matches “" + root.filterText + "”"
                color: root.foreground
                opacity: 0.65
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
              }

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                textFormat: Text.PlainText
                text: root.games.length === 0 ? "Press + (Alt+A) to add romsets, or drop them here"
                                              : "Backspace to widen the search"
                color: root.foreground
                opacity: 0.4
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // Or the launcher could not get as far as a list.
            Flickable {
              anchors.fill: parent
              visible: !root.settingsOpen && root.hasProblem
              contentHeight: problemText.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              Text {
                id: problemText
                width: parent.width
                textFormat: Text.PlainText
                text: root.problemReport
                color: root.foreground
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            // ------------------------------------------------- the stick test
            //
            // Every press on the stick, read as RetroArch will read it: the big
            // line says what the last button does in a game, and the board
            // below lights each cabinet control while it is held -- so a
            // button that lights nothing, or the wrong thing, shows at once.
            Item {
              id: padBoard
              visible: root.settingsOpen && root.padTesting
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Style.space(900))

              Column {
                id: padHeadline
                anchors.top: parent.top
                anchors.topMargin: Style.space(24)
                width: parent.width
                spacing: Style.space(8)

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: root.padState.last
                    ? root.padState.last.label + "  →  " + root.padState.last.meaning
                    : "Press a button on the stick"
                  color: root.padState.last && !root.padState.last.ok ? root.accent : root.foreground
                  opacity: root.padState.last ? 1 : 0.6
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: !!root.padState.last
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  textFormat: Text.PlainText
                  text: root.padState.last
                    ? (root.padState.last.note || " ")
                    : (root.controllerParsed.profile ? "Read as " + root.controllerParsed.profile.name
                       + ", the way RetroArch will read it in a game." : " ")
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }
              }

              Grid {
                id: padGrid
                anchors.top: padHeadline.bottom
                anchors.topMargin: Style.space(28)
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 6
                spacing: Style.space(10)
                readonly property int cell: Math.floor((padBoard.width - spacing * 5) / 6)

                Repeater {
                  model: Model.testControls()

                  Rectangle {
                    required property string modelData
                    readonly property bool lit: Model.controlHeld(root.padState, modelData)
                    readonly property string stick: Model.controlPadLabel(root.controllerParsed, modelData)
                    width: padGrid.cell
                    height: Math.round(padGrid.cell * 0.62)
                    radius: root.cornerRadius
                    color: lit ? root.accent : root.tileSurface
                    border.width: Math.max(1, Style.space(1))
                    border.color: lit ? root.accent : (stick ? root.tileBorder : Util.alpha(root.accent, 0.5))
                    Behavior on color { ColorAnimation { duration: 60 } }

                    Column {
                      anchors.centerIn: parent
                      spacing: Style.space(4)

                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: Model.controlName(modelData)
                        color: lit ? root.background : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                      }
                      Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: stick || "not on the stick"
                        color: lit ? root.background : (stick ? root.foreground : root.accent)
                        opacity: lit ? 0.85 : 0.55
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }

            // ---------------------------------------------------- the editor
            //
            // One row per key in arcade.conf. A row shows what is in effect and
            // where it came from, so a value nobody chose reads as a default
            // rather than as a setting, and Delete puts a chosen one back.
            ListView {
              id: settingsList
              // A column of label-and-value reads badly across a panel this
              // wide: the value ends up an arm's length from its name. The
              // wall gets the whole card, the editor takes a page width.
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: Math.min(parent.width, Style.space(900))
              visible: root.settingsOpen && !root.padTesting
              model: root.settingsRows.length
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              spacing: Style.space(2)

              delegate: Column {
                id: settingRow
                required property int index
                readonly property var entry: root.settingsRows[index]
                readonly property bool active: index === root.settingsIndex
                readonly property bool editingThis: index === root.editingIndex
                readonly property bool capturingThis: index === root.capturingIndex
                readonly property bool newGroup: index === 0
                  || root.settingsRows[index - 1].group !== entry.group

                width: settingsList.width
                spacing: Style.space(4)

                Item {
                  width: parent.width
                  height: settingRow.newGroup ? Style.font.caption + Style.space(16) : 0
                  visible: settingRow.newGroup

                  Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Style.space(3)
                    textFormat: Text.PlainText
                    text: settingRow.entry ? String(settingRow.entry.group).toUpperCase() : ""
                    color: root.foreground
                    opacity: 0.35
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: Style.space(2)
                  }
                }

                Rectangle {
                  width: parent.width
                  height: Math.max(Style.space(42), Style.font.body + Style.space(20))
                  radius: root.cornerRadius
                  color: settingRow.active ? Util.alpha(root.accent, 0.12) : "transparent"
                  border.width: settingRow.active ? Math.max(1, Style.space(1)) : 0
                  border.color: Util.alpha(root.accent, 0.45)
                  Behavior on color { ColorAnimation { duration: 120 } }

                  // A settings row is a claim about what the panel does, so the
                  // one thing it must never hide is that a value is merely the
                  // default. The dot marks the rows that are the user's own.
                  Rectangle {
                    id: overrideDot
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(4, Style.space(6))
                    height: width
                    radius: width / 2
                    color: root.accent
                    opacity: Model.isOverridden(settingRow.entry) ? 0.9 : 0
                  }

                  Text {
                    id: settingLabel
                    anchors.left: overrideDot.right
                    anchors.leftMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(parent.width * 0.32)
                    textFormat: Text.PlainText
                    text: settingRow.entry ? settingRow.entry.label : ""
                    color: settingRow.active ? root.accent : root.foreground
                    opacity: settingRow.active ? 1 : 0.85
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }

                  // The value, or the buffer being typed into it. Editing is
                  // drawn rather than focused: the overlay owns the keyboard
                  // exclusively, so a real text field would have to take it
                  // back from the panel and hand it over again.
                  Text {
                    id: settingValue
                    anchors.left: settingLabel.right
                    anchors.leftMargin: Style.space(12)
                    anchors.right: stepHint.left
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: settingRow.capturingThis
                      ? "press a key…"
                      : (settingRow.editingThis
                         ? root.editText
                         : (settingRow.entry && (settingRow.entry.kind === "bind" || settingRow.entry.layout)
                            ? Model.controlDisplay(settingRow.entry)
                              + (settingRow.entry.kind === "bind" && Model.controlPadLabel(root.controllerParsed, settingRow.entry.id)
                                 ? "   ·   stick: " + Model.controlPadLabel(root.controllerParsed, settingRow.entry.id) : "")
                            : Model.displayValue(settingRow.entry, root.home)
                              + (settingRow.entry && settingRow.entry.unit && settingRow.entry.value
                                 ? " " + settingRow.entry.unit : "")))
                    color: settingRow.capturingThis
                      || (!settingRow.editingThis && settingRow.entry && settingRow.entry.state === "missing")
                      ? root.accent : root.foreground
                    opacity: settingRow.capturingThis || settingRow.editingThis
                      || Model.isOverridden(settingRow.entry) ? 1 : 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: settingRow.editingThis ? Text.ElideLeft : Text.ElideMiddle
                  }

                  Rectangle {
                    id: settingCaret
                    visible: settingRow.editingThis && !settingRow.capturingThis
                    anchors.left: settingValue.left
                    anchors.leftMargin: Math.min(settingValue.contentWidth + Style.space(3), settingValue.width)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(2, Style.space(2))
                    height: Style.font.body
                    radius: width / 2
                    color: root.accent
                    opacity: caretBlink.on ? 0.9 : 0
                  }

                  // Arrow keys change a choice or a number in place; only the
                  // typed rows need Enter, so only they are told about it.
                  Text {
                    id: stepHint
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    visible: settingRow.active && !settingRow.editingThis
                    text: settingRow.entry && settingRow.entry.kind === "bind"
                      ? "Enter to bind"
                      : settingRow.entry && settingRow.entry.kind === "padtest"
                      ? "Enter to start"
                      : settingRow.entry && settingRow.entry.kind === "padinfo"
                      ? "F5 re-checks"
                      : (settingRow.entry && (settingRow.entry.kind === "choice" || settingRow.entry.kind === "number")
                         ? "← →" : "Enter to edit")
                    color: root.foreground
                    opacity: 0.35
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: if (pointerGate.moved && !root.editing) root.settingsIndex = settingRow.index
                    onClicked: {
                      if (root.editing && !settingRow.editingThis) root.cancelEdit()
                      root.settingsIndex = settingRow.index
                      if (settingRow.entry && settingRow.entry.kind === "choice") root.stepSetting(1)
                      else if (settingRow.entry && settingRow.entry.kind === "bind") root.beginCapture()
                      else if (settingRow.entry && settingRow.entry.kind === "padtest") root.startPadTest()
                      else if (settingRow.entry && settingRow.entry.kind === "padinfo") {}
                      else if (!settingRow.editingThis) root.beginEdit()
                    }
                  }
                }
              }
            }
          }

          // ------------------------------------------------------------ footer
          Item {
            width: parent.width
            height: root.footerHeight

            Rectangle {
              anchors.top: parent.top
              width: parent.width
              height: 1
              color: Util.alpha(root.foreground, 0.10)
            }

            // ---- the info bar
            Column {
              id: infoText
              visible: root.infoBarShown
              anchors.left: parent.left
              anchors.right: keycaps.left
              anchors.rightMargin: Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.statusMessage || (root.selected ? root.selected.title : "")
                color: root.statusMessage ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.round(Style.font.title * 1.5)
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.addNote || root.launchNote || Model.gameFacts(root.selected, root.now)
                color: (root.addNote && !root.addOk) || root.launchNote ? root.accent : root.foreground
                opacity: (root.addNote && !root.addOk) || root.launchNote ? 1 : 0.55
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Row {
              id: keycaps
              visible: root.infoBarShown
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(18)

              Repeater {
                model: Model.wallHints(root.stickLast && !!root.controllerParsed.pad,
                                       Model.versionCount(root.selected) > 1)

                Row {
                  required property var modelData
                  spacing: Style.space(6)

                  Repeater {
                    model: modelData.keys

                    Rectangle {
                      required property string modelData
                      anchors.verticalCenter: parent.verticalCenter
                      height: Style.font.caption + Style.space(10)
                      width: Math.max(height, capText.implicitWidth + Style.space(12))
                      radius: Math.max(3, root.cornerRadius / 2)
                      color: Util.alpha(root.foreground, 0.07)
                      border.width: Math.max(1, Style.space(1))
                      border.color: Util.alpha(root.foreground, 0.22)

                      Text {
                        id: capText
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: modelData
                        color: root.foreground
                        opacity: 0.85
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.label
                    color: root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // ---- the plain footer: settings, the stick test, setup problems
            Column {
              visible: !root.infoBarShown
              anchors.left: parent.left
              anchors.right: hintText.left
              anchors.rightMargin: Style.space(16)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.padTesting
                  ? "Controller test" + (root.controllerParsed.pad ? " · " + root.controllerParsed.pad.name : "")
                  : root.settingsOpen
                  ? (root.settingsRow ? root.settingsRow.label : "Settings")
                  : (root.statusMessage
                     || (root.selected ? root.selected.title : (root.hasProblem ? "Setup needed" : "")))
                color: root.statusMessage && !root.settingsOpen ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                elide: Text.ElideRight
              }

              // Under the name: what the setting does and where its value came
              // from, or the problem with what was just typed.
              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.padTesting
                  ? Model.controllerStatus(root.controllerParsed).text
                  : root.settingsOpen
                  ? (root.settingsError
                     || (root.capturing ? "press the key for this control — Esc cancels" : "")
                     || Model.describeState(root.settingsRow)
                     || (root.settingsRow
                         ? [root.settingsRow.help || "", Model.describeSource(root.settingsRow)]
                             .filter(function(part) { return part.length > 0 }).join("  ·  ")
                         : ""))
                  : (root.selected
                     ? root.selected.rom + "  ·  "
                       + (root.launchNote || Model.versionNote(root.selected)
                          || Model.shortenPath(root.selected.path, root.home))
                     : "")
                color: (root.settingsOpen
                        && (root.settingsError || root.capturing || Model.describeState(root.settingsRow)))
                  || (!root.settingsOpen && root.launchNote)
                  ? root.accent : root.foreground
                opacity: (root.settingsOpen
                          && (root.settingsError || root.capturing || Model.describeState(root.settingsRow)))
                  || (!root.settingsOpen && root.launchNote)
                  ? 1 : 0.45
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideMiddle
              }
            }

            Text {
              id: hintText
              visible: !root.infoBarShown
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width * 0.42)
              horizontalAlignment: Text.AlignRight
              text: root.padTesting
                ? "press buttons on the stick\nEsc or hold Home ends the test"
                : root.stickLast && root.controllerParsed.pad && !root.editing && !root.capturing
                ? Model.stickHint(root.stickView)
                : root.settingsOpen
                ? (root.capturing
                   ? "press a key · Esc cancels"
                   : (root.editing
                      ? "Enter saves · Esc cancels"
                      : "←→ changes · Enter edits\nDel resets · Esc goes back"))
                : (root.hasProblem
                   ? "Enter re-checks · Ctrl+, settings · Esc closes"
                   : "Enter plays · ←↑↓→ selects\nCtrl+, settings · F5 rescans · Esc closes")
              color: root.foreground
              opacity: 0.4
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              lineHeight: 1.25
            }
          }
        }
      }
    }

    // Files held over the panel: the card says what letting go will do.
    Rectangle {
      anchors.fill: card
      radius: card.radius
      visible: root.dropHover
      color: Util.alpha(root.background, 0.92)
      border.width: Math.max(2, Style.space(3))
      border.color: root.accent

      Column {
        anchors.centerIn: parent
        spacing: Style.space(10)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "󰇚"
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Math.round(Style.font.title * 3)
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Drop romsets to add them"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Math.round(Style.font.title * 1.5)
          font.bold: true
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          textFormat: Text.PlainText
          text: "Each one is test-loaded first; only games that run go in, with their artwork."
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
      }
    }

    DropArea {
      anchors.fill: parent
      onEntered: function(drag) {
        if (!drag.hasUrls) return
        drag.accept(Qt.CopyAction)
        root.dropHover = true
      }
      onExited: root.dropHover = false
      onDropped: function(drop) {
        root.dropHover = false
        if (!drop.hasUrls) return
        drop.accept(Qt.CopyAction)
        root.addGames(Model.droppedPaths(drop.urls))
      }
    }

  }

  // ------------------------------------------------------------- dropping
  //
  // The whole screen is the drop target while the panel is up: drag romsets
  // out of a file manager, open the panel (Super+A, or Home on the stick) with
  // the drag still held, and let go anywhere.
  Connections {
    target: panel
    function onVisibleChanged() { if (!panel.visible) root.dropHover = false }
  }

  // Long enough that a run of arrow presses is one write, short enough that
  // the file is current by the time anyone could look at it.
  Timer {
    id: writeTimer
    interval: 220
    onTriggered: root.flushSettings()
  }

  // The caret blink, kept out of the layout so nothing above re-lays out twice
  // a second.
  Timer {
    id: caretBlink
    property bool on: true
    running: root.opened
    interval: 560
    repeat: true
    onTriggered: on = !on
    onRunningChanged: if (!running) on = true
  }
}
