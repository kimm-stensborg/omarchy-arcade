.pragma library

// Pure logic for the arcade overlay: parsing what `arcade-launcher --list`
// prints, filtering it as you type, and the small formatting decisions the
// panel makes. None of it needs a running shell, so all of it is tested by
// test.js.

// "Title<TAB>/path/to/rom.zip" per line, exactly what --list prints. Lines
// without a tab are ignored rather than guessed at: a half-parsed row would
// launch the wrong file.
function parseList(text) {
  var games = []
  if (!text) return games

  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var tab = line.indexOf("\t")
    if (tab <= 0) continue

    var title = line.substring(0, tab)
    var path = line.substring(tab + 1)
    if (!title.length || !path.length) continue

    games.push({ title: title, path: path, rom: romName(path) })
  }
  return games
}

function romName(path) {
  var base = String(path).replace(/^.*\//, "")
  return base.replace(/\.[^.]*$/, "")
}

// Matching is on the title *and* the ROM name, because half of arcade memory
// is the short name: typing "bublbobl" has to find Bubble Bobble, and typing
// "snow" has to find all three Snow Bros.
function matches(game, needle) {
  return score(game, needle) >= 0
}

// Lower is better; -1 means no match. A title that starts with what you typed
// beats one that merely contains it, so "pang" puts Pang above Super Pang.
function score(game, needle) {
  if (!needle) return 2

  var title = game.title.toLowerCase()
  var rom = String(game.rom || "").toLowerCase()

  if (title.indexOf(needle) === 0) return 0
  if (rom.indexOf(needle) === 0) return 1
  if (title.indexOf(needle) >= 0) return 2
  if (rom.indexOf(needle) >= 0) return 3

  // Last resort: the words of the title, so "monster land" still finds
  // "Wonder Boy in Monster Land".
  var words = title.split(/[^a-z0-9]+/)
  for (var i = 0; i < words.length; i++) {
    if (words[i].indexOf(needle) === 0) return 4
  }
  return -1
}

// Filtered and ranked, keeping --list's alphabetical order inside each rank so
// the list never reshuffles for reasons the typist cannot see.
function filterGames(games, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (!needle) return (games || []).slice()

  var ranked = []
  for (var i = 0; i < games.length; i++) {
    var rank = score(games[i], needle)
    if (rank >= 0) ranked.push({ rank: rank, order: i, game: games[i] })
  }

  ranked.sort(function(a, b) {
    return a.rank !== b.rank ? a.rank - b.rank : a.order - b.order
  })

  var out = []
  for (var j = 0; j < ranked.length; j++) out.push(ranked[j].game)
  return out
}

function clampIndex(index, count) {
  if (count <= 0) return 0
  if (index < 0) return 0
  if (index > count - 1) return count - 1
  return index
}

// Wrapping movement for the arrow keys: from the last row, down lands on the
// first, which is what every other Omarchy panel does.
function wrapIndex(index, delta, count) {
  if (count <= 0) return 0
  return ((index + delta) % count + count) % count
}

function shortenPath(path, home) {
  var value = String(path || "")
  if (home && value.indexOf(home) === 0) return "~" + value.substring(home.length)
  return value
}

function describeCount(shown, total) {
  if (total <= 0) return "no games"
  if (shown === total) return total === 1 ? "1 game" : total + " games"
  return shown + " of " + total
}

// ------------------------------------------------------------------- grid

// Columns that fit the available width, never fewer than two: a one-column
// grid of artwork is just a list with gaps in it.
function columnsFor(width, targetTile, spacing, max) {
  var limit = max === undefined ? 8 : max
  var count = Math.round((width + spacing) / (targetTile + spacing))
  return Math.max(2, Math.min(limit, count))
}

// Grid movement clamps rather than wraps. Left and right flow across row ends
// on their own -- index 3 to index 4 is the start of the next row -- so the
// only thing to stop is running off either end of the library.
function gridTarget(index, delta, count) {
  if (count <= 0) return 0
  return clampIndex(index + delta, count)
}

// The row a tile sits in, used to keep the selection scrolled into view.
function rowOf(index, columns) {
  if (columns <= 0) return 0
  return Math.floor(index / columns)
}

// Artwork is reported asynchronously, one "rom<TAB>path" line at a time. A
// line with no path is a game the server has nothing for: remembered as an
// empty string so the panel stops asking and draws its lettered tile instead.
function withArt(map, line) {
  var tab = String(line || "").indexOf("\t")
  if (tab <= 0) return null

  var rom = line.substring(0, tab)
  var path = line.substring(tab + 1).trim()
  if (map[rom] === path) return null

  var next = {}
  for (var key in map) next[key] = map[key]
  next[rom] = path
  return next
}

function artFor(map, game) {
  if (!game || !map) return ""
  var path = map[game.rom]
  return path ? path : ""
}

// True while nothing is known about this ROM yet -- neither an image nor a
// recorded miss. The tile shows its letters either way; this only decides
// whether a quiet "looking for artwork" shimmer is warranted.
function artPending(map, game) {
  if (!game || !map) return true
  return map[game.rom] === undefined
}

// The ROMs a fetch still has to be asked about, capped so one keystroke cannot
// spawn a request for a library of thousands.
function artWanted(map, games, limit) {
  var wanted = []
  for (var i = 0; i < games.length && wanted.length < limit; i++) {
    if (map[games[i].rom] === undefined) wanted.push(games[i].rom)
  }
  return wanted
}

// Initials for a game with no artwork: two or three letters that read as a
// marquee rather than a truncated sentence.
function initials(title) {
  var words = String(title || "").toUpperCase().split(/[^A-Z0-9]+/)
  var letters = ""
  for (var i = 0; i < words.length && letters.length < 3; i++) {
    if (words[i].length) letters += words[i].charAt(0)
  }
  return letters || "?"
}

// --------------------------------------------------------------- settings

// The rows of the settings editor, in the order they are shown. Every one of
// them is a key in ~/.config/omarchy/arcade.conf: the panel edits the same
// file a person edits by hand, so there is one place a setting lives and no
// second store to disagree with it.
//
//   kind "path"   a filesystem path, typed
//   kind "text"   a free line, typed
//   kind "choice" one of `options`, stepped with the arrow keys
//   kind "number" an integer in [min, max], stepped by `step`
function settingsSchema() {
  return [
    { key: "ROM_DIR", label: "ROM directory", kind: "path", group: "Library",
      help: "Searched two levels deep for romsets." },
    { key: "ROM_EXTS", label: "ROM extensions", kind: "text", group: "Library",
      help: "Space separated, e.g. “zip 7z chd”." },
    // Typed as a path, but offered as a list wherever the launcher reports
    // which cores are installed: the answer is one of a handful of files on
    // this machine, not a path anyone should recall from memory.
    { key: "CORE_PATH", label: "libretro core", kind: "path", dynamic: true, group: "Library",
      help: "Leave empty to autodetect FBNeo, then MAME." },
    { key: "RETROARCH_CONFIG", label: "RetroArch config", kind: "path", group: "Library",
      help: "Optional arcade-only retroarch.cfg — shader, bezel, its own binds." },

    { key: "ARTWORK", label: "Artwork", kind: "choice", options: ["on", "off"], group: "Artwork",
      help: "“off” never touches the network; what is cached keeps showing." },
    { key: "ART_KINDS", label: "Prefer", kind: "choice", group: "Artwork",
      options: ["titles snaps boxarts", "titles snaps", "titles", "snaps titles", "boxarts titles snaps"],
      help: "Which artwork to try first: title screen, in-game snap, box scan." },
    { key: "ART_DIR", label: "Artwork cache", kind: "path", group: "Artwork" },

    { key: "TILE_SIZE", label: "Tile size", kind: "number", min: 140, max: 640, step: 20,
      unit: "px", group: "Panel", help: "How wide a game tile aims to be." },
    { key: "MAX_COLUMNS", label: "Tiles per row", kind: "number", min: 2, max: 12, step: 1,
      group: "Panel", help: "Most tiles the wall will put in one row." },

    { key: "TITLES_FILE", label: "Title overrides", kind: "path", group: "Files" },
    { key: "CACHE_FILE", label: "Title cache", kind: "path", group: "Files" },
    { key: "LOG_FILE", label: "RetroArch log", kind: "path", group: "Files" },
    { key: "MENU_CMD", label: "Menu command", kind: "text", dynamic: true, group: "Files",
      help: "Only used outside the shell. Empty autodetects wofi, rofi, fuzzel." }
  ]
}

// "KEY<TAB>value<TAB>source<TAB>state" per line, exactly what `arcade-launcher
// --settings` prints. CONFIG_FILE rides along in the same shape, and an
// "OPTIONS_<KEY>" line carries what that row can be arrowed through -- the
// installed cores, the dmenu programs that are actually here.
function parseSettings(text) {
  var out = { configFile: "", configPresent: false, values: ({}), options: ({}) }
  var lines = String(text || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2 || !parts[0]) continue
    var key = parts[0]
    var value = parts[1]
    var source = parts.length > 2 ? parts[2] : "default"

    if (key === "CONFIG_FILE") {
      out.configFile = value
      out.configPresent = source === "present"
      continue
    }
    if (key.indexOf("OPTIONS_") === 0) {
      var offered = []
      for (var j = 1; j < parts.length; j++) {
        if (parts[j]) offered.push(parts[j])
      }
      if (offered.length) out.options[key.substring("OPTIONS_".length)] = offered
      continue
    }
    out.values[key] = { value: value, source: source, state: parts.length > 3 ? parts[3] : "ok" }
  }
  return out
}

// The schema joined with what the launcher reported. A choice whose stored
// value is not one of the offered ones keeps it as an extra option rather
// than silently rewriting a hand-edited config on the next arrow press.
function settingsRows(parsed) {
  var schema = settingsSchema()
  var values = (parsed && parsed.values) || ({})
  var rows = []

  for (var i = 0; i < schema.length; i++) {
    var row = {}
    for (var prop in schema[i]) row[prop] = schema[i][prop]

    var known = values[row.key]
    row.value = known ? String(known.value) : ""
    row.source = known ? known.source : "default"
    row.state = known && known.state ? known.state : "ok"

    // A row the launcher offered a list for stops being a typed path: empty
    // leads the list, because "let the launcher decide" is a real answer and
    // the row already says so.
    var offered = (parsed && parsed.options ? parsed.options[row.key] : null)
    if (row.dynamic && offered && offered.length) {
      row.kind = "choice"
      row.allowEmpty = true
      row.options = [""].concat(offered)
    }

    if (row.kind === "choice") {
      row.options = (row.options || []).slice()
      if (row.value && row.options.indexOf(row.value) < 0) row.options.push(row.value)
    }
    rows.push(row)
  }
  return rows
}

// Only "file" is the user's own doing. Everything else is the launcher's
// default or its autodetection, which the editor shows but does not pretend
// was chosen.
function isOverridden(row) {
  return !!row && row.source === "file"
}

// The row's own bad news, ahead of anything else it has to say: a path that
// is not there is the reason the library will come up empty, and the row that
// holds it is where that belongs.
function describeState(row) {
  if (!row || row.state !== "missing") return ""
  return row.key === "ROM_DIR" ? "no such directory" : "no such file"
}

function describeSource(row) {
  if (!row) return ""
  if (row.source === "file") return row.kind === "bind" || row.layout ? "set for the arcade" : "set here"
  if (row.source === "retroarch") return "from your RetroArch config"
  if (row.source === "env") return "from the environment"
  if (row.source === "auto") return row.value ? "autodetected" : "nothing found"
  return "default"
}

// What a row shows when it holds nothing: an empty CORE_PATH is a decision
// ("autodetect"), an empty log path is just empty.
function displayValue(row, home) {
  if (!row) return ""
  if (row.value) return shortenPath(row.value, home)
  if (row.kind === "number") return ""
  return row.key === "CORE_PATH" || row.key === "MENU_CMD" ? "autodetect" : "none"
}

// Refused before anything is written, so a typo cannot leave the panel
// pointing at a directory that will never list a game. Returns "" when the
// value is fine, otherwise the sentence to show under the row.
function validateSetting(row, value) {
  var text = String(value === undefined || value === null ? "" : value)
  if (!row) return "unknown setting"
  if (text.indexOf("\t") >= 0 || text.indexOf("\n") >= 0) return "no tabs or newlines"

  if (row.kind === "number") {
    if (!/^-?\d+$/.test(text.trim())) return "a whole number"
    var n = parseInt(text.trim(), 10)
    if (row.min !== undefined && n < row.min) return "at least " + row.min
    if (row.max !== undefined && n > row.max) return "at most " + row.max
    return ""
  }

  if (row.kind === "choice") {
    if (!text && !row.allowEmpty) return "pick one"
    return ""
  }

  if (row.key === "ROM_DIR" && !text.trim()) return "a directory is required"
  if (row.key === "ARTWORK" && text && !/^(on|off)$/i.test(text.trim())) return "on or off"
  if (row.key === "ROM_EXTS") {
    if (!text.trim()) return "at least one extension"
    if (!/^[A-Za-z0-9 .]+$/.test(text.trim())) return "extensions, space separated"
  }
  return ""
}

// What gets typed back into the file. Extensions are stored bare, so "*.zip"
// and ".zip" both end up as "zip".
function normalizeSetting(row, value) {
  var text = String(value === undefined || value === null ? "" : value).trim()
  if (!row) return text
  if (row.kind === "number") return String(parseInt(text, 10))
  if (row.key === "ARTWORK") return text.toLowerCase()
  if (row.key === "ROM_EXTS") {
    return text.split(/\s+/).map(function(ext) {
      return ext.replace(/^\*?\./, "").toLowerCase()
    }).filter(function(ext) { return ext.length > 0 }).join(" ")
  }
  return text
}

// "KEY=VALUE" for `arcade-launcher --set`. An empty value removes the line and
// hands the setting back to its default, which is what "reset" does.
function settingArg(key, value) {
  return String(key) + "=" + String(value === undefined || value === null ? "" : value)
}

function cycleOption(options, value, delta) {
  var list = options || []
  if (list.length === 0) return value
  var at = list.indexOf(value)
  if (at < 0) at = 0
  return list[((at + delta) % list.length + list.length) % list.length]
}

// Stepping a number row. An empty or unreadable value starts from the
// default the row carries rather than from zero.
function stepNumber(row, value, delta) {
  var n = parseInt(String(value), 10)
  if (isNaN(n)) n = row && row.min !== undefined ? row.min : 0
  var step = (row && row.step) || 1
  n += delta * step
  if (row && row.min !== undefined && n < row.min) n = row.min
  if (row && row.max !== undefined && n > row.max) n = row.max
  return String(n)
}

function settingNumber(parsed, key, fallback) {
  var known = parsed && parsed.values ? parsed.values[key] : null
  var n = known ? parseInt(String(known.value), 10) : NaN
  return isNaN(n) ? fallback : n
}

// Which parts of the panel a change invalidates. Editing the ROM directory has
// to re-read the library; editing artwork policy has to forget what is known
// about every tile, or an "off" that just became "on" would never fetch.
function affectsLibrary(key) {
  return ["ROM_DIR", "ROM_EXTS", "CORE_PATH", "TITLES_FILE", "CACHE_FILE"].indexOf(key) >= 0
}

function affectsArtwork(key) {
  return ["ARTWORK", "ART_KINDS", "ART_DIR"].indexOf(key) >= 0
}

// Values the panel has taken but not yet written. Holding an arrow key steps
// faster than a process can be spawned per press, so the row shows where it is
// now and the write follows once the stepping stops.
function withPending(rows, pending) {
  if (!pending) return rows
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var row = rows[i]
    if (pending[row.key] === undefined) { out.push(row); continue }

    var copy = {}
    for (var prop in row) copy[prop] = row[prop]
    copy.value = String(pending[row.key])
    // An empty pending value is a reset: the line is on its way out of the
    // file, so the row should already read as a default rather than keeping
    // the mark that says someone chose it.
    copy.source = copy.value ? "file" : "default"
    out.push(copy)
  }
  return out
}

// One --set invocation for everything waiting, so a run of arrow presses is a
// single write of the value it ended on.
function pendingArgs(pending) {
  var args = []
  for (var key in pending) args.push(settingArg(key, pending[key]))
  return args
}

// --------------------------------------------------------------- controls
//
// The cabinet binds, kept in an arcade-only RetroArch profile. They are read
// and written through the launcher exactly as the arcade.conf settings are, so
// the editor treats both as rows and only the writing differs.

// Qt key codes, spelled out here because Model.js has to stay loadable by node
// for the tests -- there is no Qt to ask.
var KEY_ESCAPE = 0x01000000
var KEY_TAB = 0x01000001
var KEY_BACKSPACE = 0x01000003
var KEY_RETURN = 0x01000004
var KEY_ENTER = 0x01000005
var KEY_INSERT = 0x01000006
var KEY_DELETE = 0x01000007
var KEY_PAUSE = 0x01000008
var KEY_PRINT = 0x01000009
var KEY_HOME = 0x01000010
var KEY_END = 0x01000011
var KEY_LEFT = 0x01000012
var KEY_UP = 0x01000013
var KEY_RIGHT = 0x01000014
var KEY_DOWN = 0x01000015
var KEY_PAGEUP = 0x01000016
var KEY_PAGEDOWN = 0x01000017
var KEY_SHIFT = 0x01000020
var KEY_CONTROL = 0x01000021
var KEY_ALT = 0x01000023
var KEY_CAPSLOCK = 0x01000024
var KEY_NUMLOCK = 0x01000025
var KEY_SCROLLLOCK = 0x01000026
var KEY_F1 = 0x01000030
var KEY_SPACE = 0x20
var KEYPAD_MODIFIER = 0x20000000

// Keys that carry a name of their own in retroarch.cfg. Anything printable is
// handled by its text instead, so a layout that puts Z where QWERTY has Y
// binds what the key actually types.
var NAMED_KEYS = {}
NAMED_KEYS[KEY_ESCAPE] = "escape"
NAMED_KEYS[KEY_TAB] = "tab"
NAMED_KEYS[KEY_BACKSPACE] = "backspace"
NAMED_KEYS[KEY_RETURN] = "enter"
NAMED_KEYS[KEY_ENTER] = "kp_enter"
NAMED_KEYS[KEY_INSERT] = "insert"
NAMED_KEYS[KEY_DELETE] = "del"
NAMED_KEYS[KEY_PAUSE] = "pause"
NAMED_KEYS[KEY_PRINT] = "print_screen"
NAMED_KEYS[KEY_HOME] = "home"
NAMED_KEYS[KEY_END] = "end"
NAMED_KEYS[KEY_LEFT] = "left"
NAMED_KEYS[KEY_UP] = "up"
NAMED_KEYS[KEY_RIGHT] = "right"
NAMED_KEYS[KEY_DOWN] = "down"
NAMED_KEYS[KEY_PAGEUP] = "pageup"
NAMED_KEYS[KEY_PAGEDOWN] = "pagedown"
NAMED_KEYS[KEY_SHIFT] = "shift"
NAMED_KEYS[KEY_CONTROL] = "ctrl"
NAMED_KEYS[KEY_ALT] = "alt"
NAMED_KEYS[KEY_CAPSLOCK] = "capslock"
NAMED_KEYS[KEY_NUMLOCK] = "numlock"
NAMED_KEYS[KEY_SCROLLLOCK] = "scroll_lock"
NAMED_KEYS[KEY_SPACE] = "space"

// Punctuation, by what it types rather than by keycode.
var PUNCTUATION = {
  "-": "minus", "=": "equals", "[": "leftbracket", "]": "rightbracket",
  ";": "semicolon", "'": "quote", ",": "comma", ".": "period",
  "/": "slash", "\\": "backslash", "`": "backquote"
}

// The name retroarch.cfg gives the key that was just pressed, or "" for a key
// it has no name for. Shift is deliberately ignored: a cabinet binds the key,
// not the character on it, so pressing shift+1 binds "1".
function retroarchKey(key, modifiers, text) {
  var keypad = (modifiers & KEYPAD_MODIFIER) !== 0
  var letter = String(text || "")

  if (key >= KEY_F1 && key <= KEY_F1 + 11) return "f" + (key - KEY_F1 + 1)

  // Digits and letters come from the key rather than the text, so holding
  // shift still binds the 5 that was pressed and not the % it typed. Qt
  // reports the key the layout produces, so a non-QWERTY board binds what is
  // printed on it either way.
  if (key >= 0x30 && key <= 0x39) return (keypad ? "keypad" : "num") + String.fromCharCode(key)
  if (key >= 0x41 && key <= 0x5a) return String.fromCharCode(key + 32)
  if (/^[0-9]$/.test(letter)) return (keypad ? "keypad" : "num") + letter
  if (/^[a-zA-Z]$/.test(letter)) return letter.toLowerCase()
  if (PUNCTUATION[letter] !== undefined && !keypad) return PUNCTUATION[letter]
  if (keypad) {
    if (letter === "+") return "kp_plus"
    if (letter === "-") return "kp_minus"
    if (letter === ".") return "kp_period"
  }

  var named = NAMED_KEYS[key]
  return named === undefined ? "" : named
}

// The same name written for a person: "num5" is the 5 they pressed, "ctrl" is
// the left one, and an unbound control says so rather than showing RetroArch's
// "nul".
function describeBind(name) {
  var value = String(name || "")
  if (!value || value === "nul") return "unbound"

  var digits = /^num([0-9])$/.exec(value)
  if (digits) return digits[1]
  var keypad = /^keypad([0-9])$/.exec(value)
  if (keypad) return "Keypad " + keypad[1]
  if (/^f([0-9]{1,2})$/.test(value)) return value.toUpperCase()
  if (/^[a-z]$/.test(value)) return value.toUpperCase()

  var spelled = {
    shift: "Left Shift", ctrl: "Left Ctrl", alt: "Left Alt",
    rshift: "Right Shift", rctrl: "Right Ctrl", ralt: "Right Alt",
    enter: "Enter", kp_enter: "Keypad Enter", space: "Space", escape: "Esc",
    backspace: "Backspace", tab: "Tab", del: "Delete", insert: "Insert",
    home: "Home", end: "End", pageup: "Page Up", pagedown: "Page Down",
    up: "Up", down: "Down", left: "Left", right: "Right",
    minus: "-", equals: "=", leftbracket: "[", rightbracket: "]",
    semicolon: ";", quote: "'", comma: ",", period: ".", slash: "/",
    backslash: "\\", backquote: "`", kp_plus: "Keypad +", kp_minus: "Keypad -",
    kp_period: "Keypad .", capslock: "Caps Lock", numlock: "Num Lock",
    scroll_lock: "Scroll Lock", print_screen: "Print Screen", pause: "Pause"
  }
  return spelled[value] !== undefined ? spelled[value] : value
}

// The control layouts the launcher can write, and what to call them.
function layoutOptions() {
  return [
    { value: "mame", label: "MAME standard" },
    { value: "retroarch", label: "RetroArch default" }
  ]
}

function layoutLabel(value) {
  var options = layoutOptions()
  for (var i = 0; i < options.length; i++) {
    if (options[i].value === value) return options[i].label
  }
  return value === "custom" ? "custom" : String(value || "")
}

// One row per cabinet control, in the order they are shown. The ids are the
// launcher's; the numbering follows FBNeo's six-button arcade layout.
function controlsSchema() {
  return [
    { id: "coin1", label: "Insert coin", group: "Controls",
      help: "RetroPad Select. MAME puts this on 5, RetroArch on right shift." },
    { id: "start1", label: "Start", group: "Controls" },
    { id: "up1", label: "Up", group: "Controls" },
    { id: "down1", label: "Down", group: "Controls" },
    { id: "left1", label: "Left", group: "Controls" },
    { id: "right1", label: "Right", group: "Controls" },
    { id: "b1", label: "Button 1", group: "Controls",
      help: "FBNeo lays a six-button panel out as Y X L over B A R; this is Y." },
    { id: "b2", label: "Button 2", group: "Controls" },
    { id: "b3", label: "Button 3", group: "Controls" },
    { id: "b4", label: "Button 4", group: "Controls" },
    { id: "b5", label: "Button 5", group: "Controls" },
    { id: "b6", label: "Button 6", group: "Controls" },

    { id: "coin2", label: "Insert coin", group: "Player 2" },
    { id: "start2", label: "Start", group: "Player 2" },

    { id: "exit", label: "Exit game", group: "Hotkeys",
      help: "Quits RetroArch and puts you back where you were." },
    { id: "pause", label: "Pause", group: "Hotkeys" },
    { id: "menu", label: "RetroArch menu", group: "Hotkeys" }
  ]
}

// "id<TAB>key<TAB>source" per control, what `arcade-launcher --controls`
// prints, with the profile and the layout it matches on the first two lines.
function parseControls(text) {
  var out = { file: "", present: false, preset: "custom", values: ({}) }
  var lines = String(text || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2 || !parts[0]) continue

    if (parts[0] === "CONTROLS_FILE") {
      out.file = parts[1]
      out.present = parts[2] === "present"
      continue
    }
    if (parts[0] === "PRESET") {
      out.preset = parts[1] || "custom"
      continue
    }
    out.values[parts[0]] = { key: parts[1], source: parts.length > 2 ? parts[2] : "default" }
  }
  return out
}

// The layout row, then one row per control. They join the settings rows in the
// same editor, so they carry the same shape: a value to show, a source that
// says whose choice it was, and a kind that decides what a keypress does.
function controlRows(parsed) {
  var schema = controlsSchema()
  var values = (parsed && parsed.values) || ({})
  var preset = (parsed && parsed.preset) || "custom"
  var options = layoutOptions()
  var offered = []
  for (var o = 0; o < options.length; o++) offered.push(options[o].value)
  if (offered.indexOf(preset) < 0) offered.push(preset)

  var rows = [{
    key: "CONTROLS_PRESET", label: "Control layout", kind: "choice", layout: true,
    group: "Controls", options: offered, value: preset,
    // Nothing is anyone's choice until a profile exists: with none, every bind
    // is whatever RetroArch was already doing.
    source: parsed && parsed.present ? "file" : "default",
    state: "ok",
    help: "MAME standard is 5 to insert a coin, 1 to start, arrows and Ctrl / Alt / Space."
  }]

  for (var i = 0; i < schema.length; i++) {
    var row = {}
    for (var prop in schema[i]) row[prop] = schema[i][prop]

    var known = values[row.id]
    row.kind = "bind"
    row.key = "CONTROL_" + row.id
    row.value = known ? String(known.key) : ""
    row.source = known ? known.source : "default"
    row.state = "ok"
    rows.push(row)
  }
  return rows
}

// A control row shows the key, a layout row the layout's name.
function controlDisplay(row) {
  if (!row) return ""
  if (row.layout) return layoutLabel(row.value)
  return describeBind(row.value)
}
