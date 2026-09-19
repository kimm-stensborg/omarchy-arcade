.pragma library

// --------------------------------------------------------------- controls
//
// The cabinet binds, kept in an arcade-only RetroArch profile. They are read
// and written through the launcher exactly as the arcade.conf settings are, so
// the editor treats both as rows and only the writing differs.

// Qt key codes, spelled out here because these files have to stay loadable by node
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
      help: "RetroPad B. Buttons 1-6 are B A Y X R L in most games; 3-punch, 3-kick fighters put punches on Y X L." },
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
