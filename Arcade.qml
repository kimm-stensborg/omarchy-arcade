import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "Library.js" as Library
import "Browse.js" as Browse
import "Present.js" as Present
import "Controls.js" as Controls
import "Settings.js" as Settings
import "Pad.js" as Pad

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
  // Values taken but not yet in the file; see Settings.withPending.
  property var pendingSettings: ({})
  // The cabinet binds, from the arcade-only RetroArch profile.
  property var controlsParsed: ({ file: "", present: false, preset: "custom", values: ({}) })
  // The row waiting for a key to be pressed at it, or -1.
  property int capturingIndex: -1

  // The wall's order: SORT_BY from arcade.conf, or what the Sort chip was
  // just set to while that is being written there. "last played" by default,
  // so Enter on open replays the last game.
  property string sortChoice: ""
  readonly property string sortBy: Browse.sortKey(root.sortChoice
    || (root.settingsParsed.values.SORT_BY || {}).value || "")
  // Which games are shown: all, favourites, played or never played, and a
  // decade and a maker ("" is any). For this open of the panel only, like
  // the search: a wall that opens half empty would look like lost games.
  property var filters: ({ show: "all", decade: "", maker: "", genre: "", players: "" })
  // Each game once, however many regional versions of it are in the ROM
  // directory; Tab steps through them. A search shows every version, since
  // "sfiiij" is typed by someone who wants that one.
  readonly property bool groupVersions: String((root.settingsParsed.values.GROUP_VERSIONS || {}).value || "on") !== "off"
  // group -> path of the version Tab last picked, for this open of the panel.
  property var pickedVersions: ({})
  readonly property bool searching: root.filterText.trim().length > 0
  // Your games, and -- once a Show choice reaching past them has asked for
  // it -- every other game FinalBurn Neo knows, read in the background.
  property var catalogue: []
  property bool catalogueLoaded: false
  readonly property var allGames: root.catalogue.length ? root.games.concat(root.catalogue) : root.games
  readonly property var wallSource: root.groupVersions ? Library.groupGames(root.allGames, root.pickedVersions) : root.allGames
  // The games the Show chip has in view; the other filters offer only what
  // is among them, so browsing your own games never lists 400 makers.
  readonly property var scoped: root.wallSource.filter(function(g) { return Browse.inScope(g, root.filters.show) })
  // The same, every version on its own: what a search looks through.
  readonly property int searchPool: root.allGames.filter(function(g) { return Browse.inScope(g, root.filters.show) }).length
  readonly property var decadeChoices: Browse.decadeOptions(root.scoped)
  readonly property var makerChoices: Browse.makerOptions(root.scoped)
  readonly property var genreChoices: Browse.genreOptions(root.scoped)
  readonly property var playerChoices: Browse.playerOptions(root.scoped)
  // A search ranks by how well each game matches; the filters hold either way.
  readonly property var rows: root.searching
    ? Browse.applyFilters(Library.filterGames(root.allGames, root.filterText), root.filters)
    : Browse.sortGames(Browse.applyFilters(root.wallSource, root.filters), root.sortBy)
  // The selected game's title screen, blurred behind everything. It follows
  // the selection a beat late, so holding the lever does not decode a
  // picture for every tile it passes.
  property string backdrop: ""
  // The game RetroArch is running right now, if the launcher started one.
  readonly property var playing: Library.playingGame(root.games)
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
  readonly property string launchNote: Present.launchNote(root.selected, root.playing, root.gamePaused)

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
  // The sort and filter chips under the header, on the wall only.
  readonly property bool toolbarShown: !root.settingsOpen && !root.hasProblem && root.games.length > 0
  readonly property int toolbarHeight: Style.font.caption + Style.space(16)
  readonly property int footerHeight: Math.max(Style.space(76), Math.round(Style.font.title * 1.5) + Style.font.caption + Style.space(26))

  // One editor, two files: arcade.conf decides what the panel does, the arcade
  // RetroArch profile decides what the cabinet's buttons do.
  readonly property var settingsRows: root.gameRom
    ? Settings.withPending(Settings.gameRows(root.gameParsed, root.gameEntry), root.pendingGame)
    : Settings.withCheckRow(Settings.withPending(Settings.settingsRows(root.settingsParsed), root.pendingSettings),
                            root.checkState)
      .concat(Pad.controllerRows(root.controllerParsed))
      .concat(Controls.controlRows(root.controlsParsed))

  // ---- one game's settings
  // The same editor, showing one game: its name, artwork, picture and the
  // controls it changes. gameRom is the game being edited, "" for the
  // arcade-wide settings.
  property string gameRom: ""
  property string gameTitle: ""
  // The game as the wall has it, for what the editor can say about it (its
  // screen standing on its side, say).
  property var gameEntry: null

  // ---- the game underneath
  // The panel sits on top of a game it started, and RetroArch holds the game
  // still while something else has the screen (pause_nonactive, which the
  // arcade turns on for its games). The panel asks how the game is doing, so
  // its tile can say so; going back to it, or closing the panel, sets it off
  // again.
  property bool gamePaused: false
  property int stateRetries: 0

  // RetroArch takes a moment to notice it has lost the screen, so the answer
  // is asked for again a few times.
  function askGameState(tries) {
    root.stateRetries = tries
    if (!stateProc.running) stateProc.running = true
  }

  // ---- attract mode
  // Left alone on the wall, the panel shows the games' title screens one after
  // another, like a cabinet waiting for coins. Any key, button or mouse
  // movement ends it -- and does nothing else, so waking it never starts a
  // game by accident.
  property bool attract: false
  property var attractGames: []
  property int attractIndex: 0
  readonly property int attractAfter: Browse.attractSeconds(
    (root.settingsParsed.values.ATTRACT_AFTER || {}).value || "60")
  readonly property var attractGame: root.attract && root.attractGames.length
    ? root.attractGames[root.attractIndex % root.attractGames.length] : null

  function startAttract() {
    // Only games you can play: a cabinet does not advertise what it lacks.
    var order = Browse.attractOrder(root.wallSource.filter(function(g) { return g.installed !== false }),
                                     root.artMap, Date.now())
    // Two title screens at least, or it is just a picture.
    if (order.length < 2) { idleTimer.restart(); return }
    root.stopStickRepeat()
    root.attractGames = order
    root.attractIndex = 0
    root.attract = true
  }

  function stopAttract() {
    root.attract = false
    root.attractGames = []
    backdropTimer.restart()
    idleTimer.restart()
  }

  // Whatever was just done counts as someone being there. Returns true when
  // it only woke the panel, so the caller drops it.
  function wake() {
    if (root.attract) { root.stopAttract(); return true }
    idleTimer.restart()
    return false
  }

  // ---- the library check
  // Test-loading every game in the background; see Settings.libraryCheckRow.
  property string checkProgress: ""
  // What the last check found, said on its own row: the info bar that says
  // it on the wall is hidden while the settings are open.
  property string checkResult: ""
  readonly property var checkState: ({
    running: checkProc.running,
    progress: root.checkProgress,
    result: root.checkResult,
    broken: root.games.filter(function(g) { return !!g.problem }).length
  })
  property var gameParsed: Settings.parseGame("")
  property var pendingGame: ({})
  // rom -> a number bumped when its picture is replaced under the same
  // file name, so the tile does not keep showing the old one from cache.
  property var artRevision: ({})

  // ---- the stick
  // All of it lives in Stick.qml; these are what the views read.
  property alias controllerParsed: stick.controllerParsed
  property alias padTesting: stick.padTesting
  property alias padState: stick.padState
  property alias stickLast: stick.stickLast
  readonly property alias stickView: stick.view
  function startPadTest() { stick.startTest() }
  function stopPadTest() { stick.stopTest() }
  function stopStickRepeat() { stick.stopRepeat() }

  Stick { id: stick; arcade: root }
  readonly property var settingsRow: root.settingsIndex >= 0 && root.settingsIndex < root.settingsRows.length
    ? root.settingsRows[root.settingsIndex]
    : null
  readonly property bool editing: root.editingIndex >= 0
  readonly property bool capturing: root.capturingIndex >= 0

  readonly property int tileSpacing: Style.space(16)
  // Title screens want room. TILE_SIZE is the width a tile aims for and
  // MAX_COLUMNS the most that go in a row, both from arcade.conf: the defaults
  // give a wide monitor bigger art rather than more of it.
  readonly property int targetTileWidth: Math.max(Style.space(Settings.settingNumber(root.settingsParsed, "TILE_SIZE", 300)), 140)
  readonly property int cardWidth: Math.min(panel.width - Style.gapsOut * 2,
    Math.max(Style.space(1180), Math.round(panel.width * 0.72)))
  readonly property int cardHeight: Math.min(panel.height - Style.gapsOut * 2,
    Math.max(Style.space(760), Math.round(panel.height * 0.78)))
  readonly property int columns: Browse.columnsFor(wallView.grid.width, root.targetTileWidth, root.tileSpacing,
    Settings.settingNumber(root.settingsParsed, "MAX_COLUMNS", 6))
  readonly property int cellWidth: root.columns > 0 ? Math.floor(wallView.grid.width / root.columns) : root.targetTileWidth
  // 4:3 for the art, plus a caption strip underneath. Arcade screens are
  // that shape, so anything else would letterbox every tile. The caption is
  // measured in real line heights, not font sizes: a line is taller than
  // its font, and a tile sized by the font spills its last line.
  readonly property int tileInset: Style.space(6)
  readonly property int artHeight: Math.round((root.cellWidth - root.tileSpacing - root.tileInset * 2) * 0.75)
  readonly property int captionPadX: Style.space(8)
  readonly property int captionPadY: Style.space(9)
  readonly property int captionGap: Style.space(3)
  readonly property int captionHeight: Math.ceil(nameMetrics.height + noteMetrics.height)
    + root.captionGap + root.captionPadY * 2
  readonly property int cellHeight: root.artHeight + root.captionHeight + root.tileInset * 2 + root.tileSpacing

  FontMetrics { id: nameMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
  FontMetrics { id: noteMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
  readonly property real nameLineHeight: nameMetrics.height
  readonly property real noteLineHeight: noteMetrics.height

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }

    root.opened = true
    root.attract = false
    root.askGameState(5)
    root.now = Date.now() / 1000
    root.pickedVersions = ({})
    root.checkResult = ""
    root.sortChoice = ""
    root.filters = ({ show: "all", decade: "", maker: "", genre: "", players: "" })
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
    root.attract = false
    if (root.gamePaused) { root.gamePaused = false; resumeProc.running = true }
    root.stateRetries = 0
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

  // For the views in their own files: the keyboard back to the panel, the
  // gate that tells a moved pointer from a still one, the caret's blink.
  function focusKeys() { keyCatcher.forceActiveFocus() }
  readonly property var pointerGate: gate
  readonly property bool caretOn: caretBlink.on

  // ---------------------------------------------------------------- artwork

  // Ask about what is on screen first, then the rest of the library. Cached
  // images come back in the same breath as the request, so a second open is
  // dressed before it is drawn.
  function requestArt() {
    if (artProc.running || root.games.length === 0) return
    var wanted = Library.artWanted(root.artMap, root.rows, 24)
    if (wanted.length === 0) wanted = Library.artWanted(root.artMap, root.games, 24)
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
    stick.readController()
    if (!controlsProc.running) controlsProc.running = true
  }

  // Alt+E, or the pencil on a tile: this game's own settings.
  function openGame() {
    var game = root.selected
    if (!game || root.hasProblem) return
    if (game.installed === false) { root.addOk = false; root.addNote = Present.problemNote(game); return }
    root.closeSettings()
    root.gameRom = game.rom
    root.gameTitle = game.title
    root.gameEntry = game
    root.gameParsed = Settings.parseGame("")
    root.pendingGame = ({})
    root.settingsIndex = 0
    root.settingsOpen = true
    root.settingsError = ""
    root.editingIndex = -1
    gameProc.command = [root.launcher, "--game", game.rom]
    gameProc.running = true
  }

  function flushGame() {
    gameWriteTimer.stop()
    if (!root.gameRom) return
    var args = Settings.pendingArgs(root.pendingGame)
    if (args.length === 0) return
    if (gameSetProc.running) { gameWriteTimer.restart(); return }
    gameSetProc.changedKeys = Object.keys(root.pendingGame)
    gameSetProc.rom = root.gameRom
    gameSetProc.command = [root.launcher, "--game-set", root.gameRom].concat(args)
    gameSetProc.running = true
    root.pendingGame = ({})
  }

  function queueGame(key, value) {
    var pending = ({})
    for (var k in root.pendingGame) pending[k] = root.pendingGame[k]
    pending[key] = value
    root.pendingGame = pending
    gameWriteTimer.restart()
  }

  // A picture of your own: the panel steps aside for the file chooser, as it
  // does when adding games.
  function pickImage() {
    if (imageProc.running || !root.gameRom) return
    root.stopStickRepeat()
    imageProc.rom = root.gameRom
    imageProc.running = true
  }

  // The tile's picture changed: forget it, bump its revision so the image
  // cache lets go, and ask again.
  function refreshArt(rom) {
    var next = ({})
    for (var k in root.artMap) if (k !== rom) next[k] = root.artMap[k]
    root.artMap = next
    var rev = ({})
    for (var r in root.artRevision) rev[r] = root.artRevision[r]
    rev[rom] = (rev[rom] || 0) + 1
    root.artRevision = rev
    root.requestArt()
  }

  // Test-load every game not checked yet; the wall is re-read when it is done,
  // so a game that won't start shows it.
  function startCheck() {
    if (checkProc.running || addProc.running) return
    root.checkProgress = "starting…"
    checkProc.found = 0
    checkProc.checked = 0
    checkProc.running = true
  }

  function openSettings() {
    root.closeSettings()
    root.settingsOpen = true
    root.settingsError = ""
    root.editingIndex = -1
    root.loadSettings()
  }






  function closeSettings() {
    root.stopPadTest()
    root.flushSettings()
    root.flushGame()
    root.gameRom = ""
    root.settingsOpen = false
    root.editingIndex = -1
    root.settingsError = ""
  }

  function moveSetting(delta) {
    if (root.settingsRows.length === 0) return
    root.cancelEdit()
    root.settingsIndex = Browse.wrapIndex(root.settingsIndex, delta, root.settingsRows.length)
    Qt.callLater(function() { settingsView.positionViewAtIndex(root.settingsIndex, ListView.Contain) })
  }

  function beginEdit(seed) {
    var row = root.settingsRow
    if (!row || row.kind === "choice" || row.kind === "padinfo") return
    if (row.kind === "image") { root.pickImage(); return }
    if (row.kind === "bind") { root.beginCapture(); return }
    if (row.kind === "padtest") { root.startPadTest(); return }
    if (row.kind === "check") { root.startCheck(); return }
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

    var name = Controls.retroarchKey(event.key, event.modifiers, event.text)
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

    var problem = Settings.validateSetting(row, value)
    if (problem) {
      root.settingsError = problem
      return
    }

    var next = Settings.normalizeSetting(row, value)
    root.cancelEdit()
    if (next === row.value) return
    if (row.game) { root.queueGame(row.key, next); return }

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
    if (row && row.game) { root.cancelEdit(); root.queueGame(row.key, String(value)); return }
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
    var args = Settings.pendingArgs(root.pendingSettings)
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
    if (!row || !Settings.isOverridden(row)) return
    root.cancelEdit()

    // A control goes back to whatever RetroArch itself has bound; a layout row
    // has nothing to reset to, since some layout is always in force.
    if (row.layout) return
    if (row.kind === "bind") { root.applyControl(row, ""); return }
    // Taking your own picture off hands the tile back to the arcade's artwork.
    if (row.game) { root.queueGame(row.key === "ART_IMAGE" ? "ART" : row.key, ""); root.flushGame(); return }

    var pending = ({})
    for (var key in root.pendingSettings) pending[key] = root.pendingSettings[key]
    pending[row.key] = ""
    root.pendingSettings = pending
    root.flushSettings()
  }

  function stepSetting(delta) {
    var row = root.settingsRow
    if (!row || root.editing) return
    if (row.kind === "choice") root.applySetting(row, Browse.cycleOption(row.options, row.value, delta))
    else if (row.kind === "number") root.applySetting(row, Settings.stepNumber(row, row.value, delta))
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
    if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S) { root.closeSettings(); return true }
    if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_E) { root.closeSettings(); return true }
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
    if (row && ["choice", "bind", "padinfo", "padtest", "image", "check"].indexOf(row.kind) < 0) {
      if (event.key === Qt.Key_Backspace) { root.beginEdit(String(row.value).slice(0, -1)); return true }
      if (root.isTypable(event)) { root.beginEdit(String(row.value) + event.text); return true }
    }
    return false
  }

  // Every key on the wall, the editors and the stick test: the panel holds
  // the keyboard exclusively while it is up, so this is all of them.
  function handleKey(event) {
    root.stickLast = false
    if (root.wake()) { event.accepted = true; return }
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
    // Alt+S for the settings, beside Alt+A for adding games.
    if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_S) {
      root.openSettings()
      event.accepted = true
      return
    }
    // Alt+F makes the selected game a favourite; Alt+O sorts, and Alt+V,
    // Alt+D, Alt+M, Alt+G, Alt+P filter -- with Shift, the other way round.
    if ((event.modifiers & Qt.AltModifier) && !root.hasProblem) {
      var back = (event.modifiers & Qt.ShiftModifier) ? -1 : 1
      var handled = true
      if (event.key === Qt.Key_F) root.toggleFavourite()
      else if (event.key === Qt.Key_O) root.stepSort(back)
      else if (event.key === Qt.Key_V) root.stepFilter("show", back)
      else if (event.key === Qt.Key_D) root.stepFilter("decade", back)
      else if (event.key === Qt.Key_M) root.stepFilter("maker", back)
      else if (event.key === Qt.Key_G) root.stepFilter("genre", back)
      else if (event.key === Qt.Key_P) root.stepFilter("players", back)
      else if (event.key === Qt.Key_0) root.clearFilters()
      else if (event.key === Qt.Key_E) root.openGame()
      else handled = false
      if (handled) { event.accepted = true; return }
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
      if (root.selected && Library.versionCount(root.selected) > 1)
        root.pickedVersions = Library.stepVersion(root.pickedVersions, root.selected,
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

  // ------------------------------------------------------------- navigation

  // up, down, left, right, page-up, page-down; see Browse.wallMove.
  function move(action) {
    if (root.rows.length === 0) return
    gate.reset()
    if (!addProc.running) { root.statusMessage = ""; root.addNote = "" }
    root.setSelected(Browse.wallMove(root.selectedIndex, action, root.columns, 0, root.rows.length))
  }

  function setSelected(index) {
    root.selectedIndex = Browse.clampIndex(index, root.rows.length)
    Qt.callLater(function() { wallView.grid.positionViewAtIndex(root.selectedIndex, GridView.Contain) })
  }

  // The selection stays on the game it was on when the wall reorders or
  // narrows; if that game is gone, on whatever took its place.
  function keepSelection(game, fallback) {
    var key = game ? (game.groupKey || "") : ""
    for (var r = 0; game && r < root.rows.length; r++) {
      if (key ? root.rows[r].groupKey === key : root.rows[r].path === game.path) { root.setSelected(r); return }
    }
    root.setSelected(fallback)
  }

  // Alt+O, or L3 on the stick: the next order, written to arcade.conf so
  // the wall opens that way next time too.
  function stepSort(delta) {
    var game = root.selected
    var next = Browse.cycleOption(Browse.sortKeys(), root.sortBy, delta)
    root.sortChoice = next
    var pending = ({})
    for (var key in root.pendingSettings) pending[key] = root.pendingSettings[key]
    pending.SORT_BY = next
    root.pendingSettings = pending
    writeTimer.restart()
    root.keepSelection(game, 0)
  }

  // Alt+V, Alt+D, Alt+M (R3 on the stick for the first): step one filter.
  function stepFilter(which, delta) {
    var game = root.selected
    var options = which === "show" ? Browse.showKeys()
      : which === "decade" ? root.decadeChoices
      : which === "genre" ? root.genreChoices
      : which === "players" ? root.playerChoices
      : root.makerChoices
    if (options.length < 2) return
    root.filters = Browse.stepFilter(root.filters, which, options, delta)
    if (Browse.needsCatalogue(root.filters.show)) root.loadCatalogue()
    root.keepSelection(game, 0)
  }

  function clearFilters() {
    var game = root.selected
    root.filters = ({ show: "all", decade: "", maker: "", genre: "", players: "" })
    root.keepSelection(game, 0)
  }

  // Alt+F, or ZL/ZR on the stick: make the selected game a favourite, or
  // not. The wall changes at once and the selection goes with the game when
  // the order moves it; the launcher writes it down.
  function toggleFavourite() {
    var game = root.selected
    var args = Library.favouriteArgs(game)
    if (args.length === 0) return
    var on = args[0] === "--favourite"
    var roms = args.slice(1)
    var next = []
    for (var i = 0; i < root.games.length; i++) {
      var g = root.games[i]
      if (roms.indexOf(g.rom) < 0) { next.push(g); continue }
      var copy = {}
      for (var prop in g) copy[prop] = g[prop]
      copy.favourite = on
      next.push(copy)
    }
    var at = root.selectedIndex
    root.games = next
    root.addOk = true
    root.addNote = on ? game.title + " is a favourite" : game.title + " is no longer a favourite"
    root.keepSelection(game, at)
    favouriteProc.command = [root.launcher].concat(args)
    favouriteProc.running = true
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
    gate.reset()
    Qt.callLater(function() { wallView.grid.positionViewAtIndex(0, GridView.Beginning) })
  }

  // ---------------------------------------------------------------- actions

  function launch(game) {
    if (!game) return
    // The launcher lets the game go again when it brings it back, and closes
    // it when another game is picked.
    root.gamePaused = false
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
    // A game you do not have: say what it would take, rather than nothing.
    if (root.selected && root.selected.installed === false) {
      root.addOk = false
      root.addNote = Present.problemNote(root.selected)
      return
    }
    root.launch(root.selected)
  }

  // FinalBurn Neo's whole list, for the Show choices that reach past your
  // games. Read once, and again with the library, which may have taken some
  // of it in since.
  function loadCatalogue() {
    if (catalogueProc.running) return
    if (!root.catalogueLoaded) root.statusMessage = "Reading FinalBurn Neo's list of games…"
    catalogueProc.running = true
  }

  // --------------------------------------------------------------- backends

  Process {
    id: catalogueProc
    command: [root.launcher, "--list", "--all"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Only what --list did not already give: your games, and favourites
        // you do not have yet, are in root.games.
        var have = ({})
        for (var i = 0; i < root.games.length; i++) have[root.games[i].rom] = true
        var game = root.selected
        root.catalogue = Library.parseList(text).filter(function(g) { return g.installed === false && !have[g.rom] })
        root.catalogueLoaded = true
        if (root.statusMessage.indexOf("FinalBurn Neo") >= 0) root.statusMessage = ""
        root.keepSelection(game, 0)
      }
    }
  }

  Process {
    id: listProc
    command: [root.launcher, "--list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.games = Library.parseList(text)
        root.loaded = true
        if (root.catalogueLoaded || Browse.needsCatalogue(root.filters.show)) root.loadCatalogue()
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
    id: gameProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Settings.parseGame(text)
        if (parsed.rom === root.gameRom) root.gameParsed = parsed
      }
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim()) root.settingsError = Present.launcherError(text)
    }
  }

  Process {
    id: gameSetProc
    property var changedKeys: []
    property string rom: ""
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text && text.trim()) root.settingsError = Present.launcherError(text)
    }
    onExited: function(exitCode) {
      var effects = Settings.gameWriteEffects(gameSetProc.changedKeys)
      gameSetProc.changedKeys = []
      if (exitCode !== 0 && !root.settingsError) root.settingsError = "could not write this game's settings"
      if (root.gameRom === gameSetProc.rom && !gameProc.running) {
        gameProc.command = [root.launcher, "--game", gameSetProc.rom]
        gameProc.running = true
      }
      if (effects.library) root.refresh()
      if (effects.artwork) root.refreshArt(gameSetProc.rom)
      if (Settings.pendingArgs(root.pendingGame).length) gameWriteTimer.restart()
    }
  }

  // The file chooser for a game's own picture, then the copy.
  Process {
    id: imageProc
    property string rom: ""
    command: [root.launcher, "--pick-image"]
    stdout: StdioCollector { id: imageOut; waitForEnd: true }
    stderr: StdioCollector { id: imageErr; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
      var path = imageOut.text.trim().split("\n")[0]
      if (exitCode === 0 && path) {
        if (gameSetProc.running) { root.settingsError = "still saving; choose the picture again"; return }
        gameSetProc.changedKeys = ["ART_IMAGE"]
        gameSetProc.rom = imageProc.rom
        gameSetProc.command = [root.launcher, "--game-image", imageProc.rom, path]
        gameSetProc.running = true
      } else if (imageErr.text && imageErr.text.trim()) {
        root.settingsError = Present.launcherError(imageErr.text)
      }
    }
  }

  // How the game underneath is doing: "paused" while the panel has the
  // screen, "playing" once it gives it back.
  Process {
    id: stateProc
    command: [root.launcher, "--playing"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.gamePaused = text.trim() === "paused"
        if (root.opened && !root.gamePaused && root.stateRetries > 0) {
          root.stateRetries = root.stateRetries - 1
          stateRetry.restart()
        }
      }
    }
  }

  Timer {
    id: stateRetry
    interval: 350
    onTriggered: if (root.opened && !stateProc.running) stateProc.running = true
  }

  Process {
    id: resumeProc
    command: [root.launcher, "--resume"]
  }

  Process {
    id: checkProc
    property int found: 0
    property int checked: 0
    command: [root.launcher, "--check"]
    stdout: SplitParser {
      onRead: function(line) {
        var progress = Present.addProgress(line)
        if (progress) { root.checkProgress = progress; root.statusMessage = progress; return }
        var verdict = line.split("\t")[0]
        if (verdict === "broken") checkProc.found++
        if (verdict === "ok" || verdict === "broken") checkProc.checked++
      }
    }
    onExited: function(exitCode) {
      root.checkProgress = ""
      root.statusMessage = ""
      root.addOk = checkProc.found === 0
      root.addNote = exitCode !== 0 ? "The library could not be checked"
        : checkProc.checked === 0 ? "Every game was checked before; nothing has changed since"
        : "Checked " + checkProc.checked + (checkProc.checked === 1 ? " game" : " games")
          + (checkProc.found ? "  ·  " + checkProc.found + " won't start" : "  ·  all of them start")
      root.checkResult = root.addNote
      root.refresh()
    }
  }

  Process {
    id: favouriteProc
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text) root.addNote = Present.launcherError(text)
    }
    // The file is the truth: if it could not be written, the wall goes back
    // to what it says.
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.addOk = false; root.refresh() }
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
        var next = Library.withArt(root.artMap, line)
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
      onStreamFinished: root.settingsParsed = Settings.parseSettings(text)
    }
  }

  Process {
    id: addProc
    // Line by line, so a big drop counts through in the info bar.
    stdout: SplitParser {
      onRead: function(line) {
        root.addOutput += line + "\n"
        var progress = Present.addProgress(line)
        if (progress) root.statusMessage = progress
      }
    }
    onRunningChanged: {
      if (running) return
      var summary = Present.addSummary(root.addOutput)
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
        root.addNote = Present.launcherError(pickErr.text)
        root.addOk = false
      }
    }
  }





  Timer {
    id: backdropTimer
    interval: 140
    onTriggered: root.backdrop = Library.artFor(root.artMap, root.selected)
  }
  onSelectedChanged: backdropTimer.restart()
  onArtMapChanged: if (!root.backdrop) backdropTimer.restart()



  Process {
    id: controlsProc
    command: [root.launcher, "--controls"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.controlsParsed = Controls.parseControls(text)
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
        if (Settings.affectsLibrary(keys[i])) library = true
        if (Settings.affectsArtwork(keys[i])) artwork = true
      }
      // Artwork policy changed: forget what is known about every tile, or an
      // ARTWORK that just went back on would never ask for anything again.
      if (artwork) root.artMap = ({})
      if (library) root.refresh()
      else if (artwork) root.requestArt()
      if (Settings.pendingArgs(root.pendingSettings).length) writeTimer.restart()
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
    id: gate
    referenceItem: card
  }


  // ------------------------------------------------------------------- view

  PanelWindow {
    id: panel
    // Hidden, not closed, while the file chooser is open.
    visible: root.opened && !pickProc.running && !imageProc.running
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
      // Out of the way while the title screens run.
      opacity: root.attract ? 0 : 1
      visible: opacity > 0
      Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
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
        Keys.onPressed: function(event) { root.handleKey(event) }

        Column {
          anchors.fill: parent
          spacing: root.contentSpacing

          Header { width: parent.width; arcade: root }

          Toolbar { width: parent.width; arcade: root }

          // -------------------------------------------------------------- body
          Item {
            width: parent.width
            height: parent.height - root.headerHeight - root.footerHeight - root.contentSpacing * 2
              - (root.toolbarShown ? root.toolbarHeight + root.contentSpacing : 0)

            Wall { id: wallView; arcade: root }
            PadTest { arcade: root }
            SettingsList { id: settingsView; arcade: root }
          }

          // ------------------------------------------------------------ footer
          Footer { width: parent.width; arcade: root }
        }
      }
    }

    AttractMode { anchors.fill: parent; arcade: root }

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
        root.addGames(Library.droppedPaths(drop.urls))
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
  // Quiet for ATTRACT_AFTER seconds on the wall: title screens take over.
  Timer {
    id: idleTimer
    interval: Math.max(1, root.attractAfter) * 1000
    running: root.opened && root.attractAfter > 0 && !root.attract && !root.settingsOpen
      && !root.hasProblem && !checkProc.running && !addProc.running
    onTriggered: root.startAttract()
  }

  // One title screen at a time, long enough to take in.
  Timer {
    id: attractStep
    interval: 6500
    repeat: true
    running: root.attract
    onTriggered: root.attractIndex = root.attractIndex + 1
  }
  onAttractGameChanged: if (root.attractGame) root.backdrop = Library.artFor(root.artMap, root.attractGame)

  Timer {
    id: gameWriteTimer
    interval: 220
    onTriggered: root.flushGame()
  }

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
