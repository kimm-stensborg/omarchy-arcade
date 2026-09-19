.pragma library
.import "Present.js" as Present
.import "Controls.js" as Controls

// The arcade-wide settings (arcade.conf, through the launcher) and one
// game's own (its arcade-games/<rom>.cfg): the rows the editor shows, how a
// value reads, what may be written. Pure, like the rest, so test.js checks it.

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
      help: "Optional arcade-only retroarch.cfg — shader, bezel. The arcade binds are layered over it." },

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
    { key: "GROUP_VERSIONS", label: "Versions", kind: "choice", options: ["on", "off"], group: "Panel",
      help: "“on” shows each game once, however many regional versions you have; Tab switches." },
    { key: "ATTRACT_AFTER", label: "Attract mode", kind: "choice", group: "Panel",
      options: ["off", "30", "60", "120", "300"],
      labels: { off: "off", "30": "after 30 seconds", "60": "after a minute", "120": "after 2 minutes", "300": "after 5 minutes" },
      help: "Left alone, the panel shows the games' title screens one after another, like a cabinet waiting for coins." },
    { key: "SORT_BY", label: "Sort by", kind: "choice", group: "Panel",
      options: ["last played", "favourites", "most played", "name", "year"],
      help: "The order of the wall. Alt+O on the wall changes it too." },

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
  return !!row && (row.source === "file" || row.source === "game")
}

// The row's own bad news, ahead of anything else it has to say: a path that
// is not there is the reason the library will come up empty, and the row that
// holds it is where that belongs.
function describeState(row) {
  if (!row || row.state !== "missing") return ""
  if (row.kind === "check") return "Show › Won't start (Alt+V) lists them, each with its reason."
  if (row.kind === "padinfo") return row.status.text
  return row.key === "ROM_DIR" ? "no such directory" : "no such file"
}

function describeSource(row) {
  if (!row) return ""
  if (row.game) {
    if (row.kind === "image") return row.value ? "your own picture is on the tile" : ""
    if (isOverridden(row)) return "set for this game only"
    if (row.kind === "bind") return "the arcade's control, shared by every game"
    if (row.key === "TITLE") return "the database's name"
    if (row.key === "ART") return "the arcade's artwork order"
    return "as RetroArch has it"
  }
  if (row.kind === "padinfo") return row.status.text
  if (row.kind === "padtest") return ""
  if (row.kind === "check") return row.status || ""
  if (row.source === "file") return row.kind === "bind" || row.layout ? "set for the arcade" : "set here"
  if (row.source === "retroarch") return "from your RetroArch config"
  if (row.source === "env") return "from the environment"
  if (row.source === "auto") return row.value ? "autodetected" : "nothing found"
  return row.kind === "bind" ? "RetroArch's default" : "default"
}

// What a row shows when it holds nothing: an empty CORE_PATH is a decision
// ("autodetect"), an empty log path is just empty.
function displayValue(row, home) {
  if (!row) return ""
  if (row.labels) return row.labels[row.value] !== undefined ? row.labels[row.value] : row.value
  if (row.value) return Present.shortenPath(row.value, home)
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

// ------------------------------------------------------------ one game
//
// A game's own settings, what `arcade-launcher --game ROM` prints: its title,
// artwork, picture and the controls it changes. Everything not set for the
// game follows the arcade (or RetroArch), and the editor says which.

function parseGame(text) {
  var out = { rom: "", file: "", present: false, values: ({}), options: ({}), binds: ({}) }
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (!parts[0]) continue
    if (parts[0] === "GAME") { out.rom = parts[1] || ""; out.present = parts[2] === "present"; continue }
    if (parts[0] === "GAME_FILE") { out.file = parts[1] || ""; continue }
    if (parts[0] === "BIND" && parts.length >= 3) {
      out.binds[parts[1]] = { key: parts[2], source: parts[3] || "shared" }
      continue
    }
    if (parts[0].indexOf("OPTIONS_") === 0) {
      out.options[parts[0].substring("OPTIONS_".length)] = parts.slice(1).filter(function(p) { return p.length > 0 })
      continue
    }
    if (parts.length >= 2) out.values[parts[0]] = { value: parts[1], source: parts[2] || "default" }
  }
  return out
}

// "crt/crt-royale.slangp" as "crt-royale".
function shaderLabel(path) {
  return String(path || "").replace(/^.*\//, "").replace(/\.slangp$/, "")
}

function gameSchema() {
  return [
    { key: "TITLE", label: "Name", kind: "text", group: "Game",
      help: "The name on the wall and in search. Empty goes back to the database's." },
    { key: "CONTINUE", label: "Continue where you left off", kind: "choice", group: "Game",
      options: ["", "on", "off"],
      labels: { "": "as RetroArch", on: "on", off: "off" },
      help: "The game's state is saved as it closes and picked up again the next time you play it." },
    { key: "ART", label: "Artwork", kind: "choice", group: "Artwork",
      options: ["", "titles", "snaps", "boxarts"],
      labels: { "": "as the arcade", titles: "title screen", snaps: "in-game", boxarts: "box art", custom: "your own picture" },
      help: "Which picture the tile shows. Changing it fetches that kind." },
    { key: "ART_IMAGE", label: "Your own picture", kind: "image", group: "Artwork",
      labels: { "": "none", custom: "on the tile" },
      help: "A PNG or JPEG of your own for the tile. Enter opens a file chooser." },
    { key: "SHADER", label: "Shader", kind: "choice", group: "Picture", options: ["", "none"],
      labels: { "": "as RetroArch", none: "none" },
      help: "A look for the picture, a CRT's scanlines and glow for instance." },
    { key: "SMOOTH", label: "Smoothing", kind: "choice", group: "Picture", options: ["", "sharp", "smooth"],
      labels: { "": "as RetroArch", sharp: "sharp pixels", smooth: "smoothed" },
      help: "Sharp keeps every pixel square; smoothed blurs them together." },
    { key: "ASPECT", label: "Shape", kind: "choice", group: "Picture", options: ["", "core", "4:3", "full", "square"],
      labels: { "": "as RetroArch", core: "the game's own", "4:3": "4:3", full: "fill the screen", square: "square pixels" },
      help: "The shape of the picture. The game's own is what the cabinet showed." },
    { key: "INTEGER", label: "Whole-number scaling", kind: "choice", group: "Picture", options: ["", "on", "off"],
      labels: { "": "as RetroArch", on: "on", off: "off" },
      help: "Scales only by whole numbers: every pixel the same size, with a border round the picture." },
    { key: "ROTATE", label: "Rotation", kind: "choice", group: "Picture", options: ["", "0", "90", "180", "270"],
      labels: { "": "as RetroArch", "0": "0°", "90": "90°", "180": "180°", "270": "270°" },
      help: "Turns the picture, for a screen mounted on its side." }
  ]
}

// The game's rows for the editor: its settings, then the controls, each
// saying whether it is this game's own or the arcade's.
// The Library group's last row: test-load every game and remember which
// start. `state` is { running, progress, broken, total }: what the check is
// doing now, and how many games are known not to start.
// The rows with the check row placed last in the Library group, where it
// belongs beside the ROM directory it tests.
function withCheckRow(rows, state) {
  var out = (rows || []).slice()
  var at = 0
  for (var i = 0; i < out.length; i++) if (out[i].group === "Library") at = i + 1
  out.splice(at, 0, libraryCheckRow(state))
  return out
}

function libraryCheckRow(state) {
  var st = state || ({})
  var value = st.running ? (st.progress || "checking…")
    : st.result ? st.result
    : (st.broken ? st.broken + (st.broken === 1 ? " game won't start" : " games won't start")
                 : "load every game once, see which start")
  return { key: "LIBRARY_CHECK", label: "Check the library", kind: "check", group: "Library",
           source: "check", state: st.broken && !st.running ? "missing" : "ok", value: value,
           status: st.running ? "Loading each game with no window or sound, the way adding one does."
             : "Games checked before are only checked again when their file changes.",
           help: "Test-loads every game, the way adding one does, and marks the ones that won't start." }
}

function gameRows(parsed, game) {
  var p = parsed || parseGame("")
  var values = p.values || ({})
  var rows = []
  var schema = gameSchema()
  for (var i = 0; i < schema.length; i++) {
    var row = {}
    for (var prop in schema[i]) row[prop] = schema[i][prop]
    row.game = true
    row.state = "ok"
    row.allowEmpty = true
    if (row.key === "ART_IMAGE") {
      var art = values.ART ? values.ART.value : ""
      row.value = art === "custom" ? "custom" : ""
      row.source = row.value ? "game" : "default"
    } else {
      var known = values[row.key]
      row.value = known ? String(known.value) : ""
      row.source = known ? known.source : "default"
    }
    // A game made for a screen standing on its side: rotation is how it
    // fills a monitor turned the same way.
    if (row.key === "ROTATE" && game && game.vertical)
      row.help = "This game's screen stands on its side. On a monitor turned the same way, 90° or 270° fills it."
    if (row.key === "SHADER") {
      var offered = (p.options && p.options.SHADER) || []
      var labels = { "": "as RetroArch", none: "none" }
      for (var o = 0; o < offered.length; o++) {
        if (row.options.indexOf(offered[o]) < 0) row.options.push(offered[o])
        labels[offered[o]] = shaderLabel(offered[o])
      }
      if (row.value && !labels[row.value]) labels[row.value] = shaderLabel(row.value)
      row.labels = labels
    }
    if (row.kind === "choice") {
      row.options = row.options.slice()
      if (row.value && row.options.indexOf(row.value) < 0) row.options.push(row.value)
    }
    rows.push(row)
  }

  var controls = Controls.controlsSchema()
  for (var c = 0; c < controls.length; c++) {
    var bind = {}
    for (var cp in controls[c]) bind[cp] = controls[c][cp]
    var b = (p.binds || ({}))[bind.id]
    bind.kind = "bind"
    bind.game = true
    bind.key = bind.id
    bind.group = bind.group === "Controls" ? "Controls for this game" : bind.group + " for this game"
    bind.value = b ? String(b.key) : ""
    bind.source = b && b.source === "game" ? "game" : "shared"
    bind.state = "ok"
    rows.push(bind)
  }
  return rows
}

// Which parts of the panel a game's write touches: its name is the wall's,
// its artwork the tile's.
function gameWriteEffects(keys) {
  var out = { library: false, artwork: false }
  var list = keys || []
  for (var i = 0; i < list.length; i++) {
    if (list[i] === "TITLE") out.library = true
    if (list[i] === "ART" || list[i] === "ART_IMAGE") out.artwork = true
  }
  return out
}
