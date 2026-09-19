.pragma library
.import "Controls.js" as Controls

// ---------------------------------------------------------------- the stick
//
// What `arcade-launcher --controller` reports: the game controller RetroArch
// will give player 1, the autoconfig profile RetroArch matches it with, which
// of its buttons that profile puts on each RetroPad button, and what RetroArch
// itself said about controllers at the last launch.

// Which RetroPad button each cabinet control is, player 1 only: the stick
// is one player's.
var CONTROL_RETROPAD = {
  coin1: "select", start1: "start", up1: "up", down1: "down", left1: "left", right1: "right",
  b1: "b", b2: "a", b3: "y", b4: "x", b5: "r", b6: "l", exit: "menu_toggle"
}

// What a RetroPad button does in an FBNeo game: the Classic layout, and the
// layout 3-punch, 3-kick fighters switch to.
var RETROPAD_MEANING = {
  select: { control: "coin1", name: "Insert coin" },
  start: { control: "start1", name: "Start" },
  up: { control: "up1", name: "Up" }, down: { control: "down1", name: "Down" },
  left: { control: "left1", name: "Left" }, right: { control: "right1", name: "Right" },
  b: { control: "b1", name: "Button 1", fighter: "Light Kick" },
  a: { control: "b2", name: "Button 2", fighter: "Medium Kick" },
  y: { control: "b3", name: "Button 3", fighter: "Light Punch" },
  x: { control: "b4", name: "Button 4", fighter: "Medium Punch" },
  r: { control: "b5", name: "Button 5", fighter: "Heavy Kick" },
  l: { control: "b6", name: "Button 6", fighter: "Heavy Punch" },
  menu_toggle: { control: "exit", name: "Back to the arcade", note: "In a game, closes it and opens the panel." }
}

function parseController(text) {
  var out = { pad: null, profile: null, binds: ({}), seen: [] }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts[0] === "PAD" && parts.length >= 4) {
      out.pad = { name: parts[1], ids: parts[2], device: parts[3], dpad: parts[4] || "" }
    } else if (parts[0] === "PROFILE" && parts.length >= 2) {
      out.profile = { file: parts[1], name: parts[2] || "" }
    } else if (parts[0] === "BIND" && parts.length >= 3) {
      out.binds[parts[1]] = { spec: parts[2], label: parts[3] || "" }
    } else if (parts[0] === "SEEN" && parts.length >= 3) {
      out.seen.push({ port: parseInt(parts[1], 10), name: parts[2] })
    }
  }
  return out
}

// "D-Pad Up" says the same as the row it sits in; the lever is the lever.
function padLabel(controller, retropad) {
  var bind = controller && controller.binds ? controller.binds[retropad] : null
  if (!bind) return ""
  if (/^h\d+(up|down|left|right)$/.test(bind.spec)) return "lever"
  return bind.label || ("button " + bind.spec)
}

// The stick button on a cabinet control's row, or "".
function controlPadLabel(controller, controlId) {
  var retropad = CONTROL_RETROPAD[controlId]
  return retropad ? padLabel(controller, retropad) : ""
}

// Whether the stick will work in a game, as one line with a verdict:
// "ok" when RetroArch said so at the last launch, "ready" when everything
// needed is in place but no game has been started with it yet, "problem"
// otherwise.
function controllerStatus(controller) {
  var c = controller || ({})
  if (!c.pad) return { state: "problem", text: "No controller connected. Plug it in and press F5." }
  if (!c.profile) {
    return { state: "problem",
             text: "RetroArch has no profile for “" + c.pad.name + "”, so games will not know its buttons." }
  }
  if (c.pad.dpad === "none") {
    return { state: "problem",
             text: "The lever reports as an analog stick, which FBNeo ignores. Set the stick's switch to D-pad (DP)." }
  }
  for (var i = 0; i < c.seen.length; i++) {
    if (c.seen[i].name === c.pad.name && c.seen[i].port === 1)
      return { state: "ok", text: "RetroArch set it up as player 1 at the last launch, as " + c.profile.name + "." }
  }
  return { state: "ready",
           text: "RetroArch will use its " + c.profile.name + " profile. Start a game once to confirm." }
}

// One line from `arcade-pad --watch` applied to the test's state: which
// RetroPad buttons are held, and what the last press was.
// A press line from arcade-pad, as the RetroPad button RetroArch's profile
// makes of it: { kind, which, down, retropad }, retropad "" when the profile
// binds nothing there. Null for anything that is not a press line.
function padPress(controller, line) {
  var parts = String(line || "").split("\t")
  if (parts.length < 3) return null
  var kind = parts[0], which = parts[1], down = parts[2] === "1"

  var spec = kind === "button" ? which : (kind === "hat" ? "h0" + which : (kind === "axis" ? which : null))
  if (spec === null) return null

  var retropad = ""
  var binds = (controller && controller.binds) || ({})
  for (var key in binds) {
    if (binds[key].spec === spec) { retropad = key; break }
  }
  return { kind: kind, which: which, down: down, retropad: retropad }
}

function padEvent(state, controller, line) {
  var press = padPress(controller, line)
  if (!press) return null
  var kind = press.kind, which = press.which, down = press.down, retropad = press.retropad

  var held = {}
  for (var h in (state && state.held) || ({})) held[h] = state.held[h]
  if (retropad) {
    if (down) held[retropad] = true
    else delete held[retropad]
  }

  var last = state ? state.last : null
  if (down) last = describePress(controller, kind, which, retropad)
  return { held: held, last: last, presses: (state ? state.presses : 0) + (down ? 1 : 0) }
}

// What one press means, in words: the stick's name for it, and what a game
// does with it.
function describePress(controller, kind, which, retropad) {
  var meaning = RETROPAD_MEANING[retropad]
  var label = retropad ? padLabel(controller, retropad) : ""
  if (kind === "axis" && !meaning) {
    return { label: "Analog stick", meaning: "not seen by arcade games",
             note: "Set the stick's switch to D-pad (DP) so the lever works in games.", ok: false }
  }
  if (!retropad) {
    return { label: kind === "button" ? "Button " + which : which, meaning: "not bound in RetroArch",
             note: "RetroArch's profile gives this button nothing to do.", ok: false }
  }
  if (!meaning) {
    return { label: label || retropad, meaning: "not used by arcade games",
             note: "RetroPad " + retropad.toUpperCase() + " — FBNeo leaves it free.", ok: false }
  }
  if (label === "lever") label = "Lever " + meaning.name.toLowerCase()
  return { label: label, meaning: meaning.name, control: meaning.control,
           note: meaning.fighter ? "“" + meaning.fighter + "” in 3-punch, 3-kick fighters." : (meaning.note || ""),
           ok: true }
}

// What a stick press does in the panel, by RetroPad button so it holds for
// any controller RetroArch has a profile for. B and Start play, the way a
// cabinet's Button 1 and Start do; A goes back, Home closes. L2 and R2 --
// triggers no arcade game uses -- make a game a favourite, and the stick
// clicks L3 and R3 step the sort order and which games are shown.
//
//   view "wall"      the games; "problem" when the launcher reported one
//   view "settings"  the editor
function stickAction(retropad, view) {
  var directions = { up: "up", down: "down", left: "left", right: "right" }
  if (view === "settings") {
    if (directions[retropad]) return directions[retropad]
    if (retropad === "b" || retropad === "start") return "activate"
    if (retropad === "a" || retropad === "select") return "back"
    if (retropad === "menu_toggle") return "close"
    return ""
  }
  if (view === "problem") {
    if (retropad === "b" || retropad === "start") return "recheck"
    if (retropad === "a" || retropad === "menu_toggle") return "close"
    if (retropad === "select") return "settings"
    return ""
  }
  if (directions[retropad]) return directions[retropad]
  var wall = {
    b: "play", start: "play", a: "back", select: "settings", menu_toggle: "close",
    y: "version-prev", x: "version-next", l: "page-up", r: "page-down",
    l2: "favourite", r2: "favourite", l3: "sort", r3: "show"
  }
  return wall[retropad] || ""
}

// Held down, these keep going: a lever held right runs along the wall.
function stickRepeats(action) {
  return ["up", "down", "left", "right", "page-up", "page-down"].indexOf(action) >= 0
}

// The footer's word on the stick, when one is plugged in.
function stickHint(view) {
  if (view === "settings") return "stick: B changes · A goes back"
  if (view === "problem") return "stick: B re-checks · Home closes"
  return "stick: B plays · Y X versions\nA back · Home closes"
}

// The editor's Controller section: what is plugged in and whether it will
// work, then the way into the test.
function controllerRows(controller) {
  var c = controller || ({})
  var status = controllerStatus(c)
  return [
    { key: "PAD_STATUS", label: "Controller", kind: "padinfo", group: "Controller", source: "pad",
      value: c.pad ? (c.profile ? c.profile.name : c.pad.name) : "none connected",
      state: status.state === "problem" ? "missing" : "ok", status: status },
    { key: "PAD_TEST", label: "Test the stick", kind: "padtest", group: "Controller", source: "pad",
      value: c.pad ? "press each button, see what it does" : "", state: "ok",
      help: "Shows what every button and lever direction does in a game, as you press it." }
  ]
}

// The cabinet controls the test lights up, in panel order.
function testControls() {
  return ["coin1", "start1", "up1", "down1", "left1", "right1", "b1", "b2", "b3", "b4", "b5", "b6"]
}

function controlName(controlId) {
  for (var key in RETROPAD_MEANING) {
    if (RETROPAD_MEANING[key].control === controlId) return RETROPAD_MEANING[key].name
  }
  return controlId
}

function controlHeld(state, controlId) {
  var retropad = CONTROL_RETROPAD[controlId]
  return !!(state && state.held && retropad && state.held[retropad])
}

// A control row shows the key, a layout row the layout's name.
function controlDisplay(row) {
  if (!row) return ""
  if (row.layout) return Controls.layoutLabel(row.value)
  return Controls.describeBind(row.value)
}

// The stick's name for the button that makes a game a favourite: the first of ZR/ZL
// (RetroPad R2, L2) its profile binds, or "".
function favouriteStickKey(controller) {
  return padLabel(controller, "r2") || padLabel(controller, "l2")
}
