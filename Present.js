.pragma library
.import "Library.js" as Library

// What the panel says about a game: the facts line, the note under a tile,
// the footer's keycaps and warnings, how a drop of romsets went. Pure, like
// the rest, so test.js checks it.

// ------------------------------------------------------------ about a game

function playersLabel(n) {
  if (!n) return "Any players"
  return n === "1" || n === 1 ? "1 player" : n + " players"
}

// The footer's word on a game that won't start, or is not here: why, and
// what to do.
function problemNote(game) {
  if (game && game.installed === false)
    return "Not in your collection. FinalBurn Neo plays it as " + game.rom + ".zip; Alt+A adds a romset"
  var why = Library.problemOf(game)
  return why ? "Won't start: " + why : ""
}

// What the empty wall says when the filters leave nothing.
function emptyNote(filters) {
  var f = filters || ({})
  if (f.show === "favourites" && !f.decade && !f.maker) return "No favourites yet. Alt+F on a game adds it."
  if (f.show === "unplayed" && !f.decade && !f.maker) return "You have played every game here."
  if (f.show === "broken" && !f.decade && !f.maker && !f.genre && !f.players)
    return "Every game checked so far starts. Settings › Check the library tests the rest."
  return "No games match these filters."
}

// The line under the selected game's name: who made it and when, how many
// versions there are, and when it was last played.
function gameFacts(game, now) {
  if (!game) return ""
  var facts = []
  if (game.maker) facts.push(game.maker)
  if (game.year) facts.push(game.year)
  if (game.genres && game.genres.length) facts.push(game.genres.join(" / "))
  if (game.players) facts.push(playersLabel(game.players))
  if (game.vertical) facts.push("vertical screen")
  if (Library.versionCount(game) > 1) facts.push(Library.versionCount(game) + " versions")
  if (game.playing) facts.push("playing now")
  else if (Library.latestPlay(game)) facts.push("played " + playedAgo(Library.latestPlay(game), now))
  var plays = Library.playCount(game)
  if (plays) facts.push(plays === 1 ? "1 play" : plays + " plays")
  if (game.path) facts.push(String(game.path).replace(/^.*\//, ""))
  return facts.join("  ·  ")
}

// The controls at the foot of the wall, as keycaps and what they do. They
// speak whichever was used last -- keyboard or stick -- and only mention
// versions when the selected game has some. `favourite` is
// { on, stickKey }: whether the selected game is a favourite, and the
// stick's name for the button that makes it one ("" when it has none).
function wallHints(stick, versions, favourite) {
  var fav = favourite || ({})
  var star = fav.on ? "Unfavourite" : "Favourite"
  if (stick) {
    var out = [{ keys: ["B"], label: "Play" }]
    if (versions) out.push({ keys: ["Y", "X"], label: "Version" })
    if (fav.stickKey) out.push({ keys: [fav.stickKey], label: star })
    out.push({ keys: ["−"], label: "Settings" })
    out.push({ keys: ["Home"], label: "Close" })
    return out
  }
  var keys = [{ keys: ["Enter"], label: "Play" }]
  if (versions) keys.push({ keys: ["Tab"], label: "Version" })
  if (favourite) keys.push({ keys: ["Alt", "F"], label: star })
  if (favourite) keys.push({ keys: ["Alt", "E"], label: "Edit" })
  keys.push({ keys: ["Alt", "A"], label: "Add" })
  keys.push({ keys: ["Alt", "S"], label: "Settings" })
  keys.push({ keys: ["Esc"], label: "Close" })
  return keys
}

// ------------------------------------------------------------ adding games

// What `arcade-launcher --add` said, one "result<TAB>name<TAB>detail" line per
// dropped file, summed up for the info bar: a headline, the first reason
// something was turned away, and which games came in so the wall can go to
// the first of them.
function addSummary(text) {
  var counts = { added: 0, bios: 0, exists: 0, rejected: 0, conflict: 0, skipped: 0 }
  var first = {}
  var added = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2 || counts[parts[0]] === undefined) continue
    var entry = { name: parts[1], detail: parts[2] || "" }
    counts[parts[0]]++
    if (!first[parts[0]]) first[parts[0]] = entry
    if (parts[0] === "added") added.push(Library.romName(parts[1]))
  }

  var pieces = []
  if (counts.added === 1) pieces.push("Added " + (first.added.detail || first.added.name))
  else if (counts.added > 1) pieces.push("Added " + counts.added + " games")
  if (counts.bios === 1) pieces.push("BIOS " + first.bios.name + " added")
  else if (counts.bios > 1) pieces.push(counts.bios + " BIOS sets added")
  if (counts.exists === 1) pieces.push((first.exists.detail || first.exists.name) + " is already in your collection")
  else if (counts.exists > 1) pieces.push(counts.exists + " already in your collection")
  var turned = counts.rejected + counts.conflict + counts.skipped
  if (turned > 0) pieces.push(turned === 1 && pieces.length === 0 ? "Not added" : turned + " not added")

  var why = first.rejected || first.conflict || first.skipped
  return {
    title: pieces.join("  ·  ") || "Nothing to add",
    detail: why ? why.name + ": " + why.detail + (turned > 1 ? "  (+" + (turned - 1) + " more)" : "") : "",
    added: added,
    ok: turned === 0
  }
}

// "checking<TAB>name<TAB>n<TAB>of" from --add, as the info bar says it while
// a drop is being worked through; "" for any other line.
function addProgress(line) {
  var parts = String(line || "").split("\t")
  if (parts[0] !== "checking" || parts.length < 4) return ""
  return parts[3] === "1" ? "Checking " + parts[1] + "…" : "Checking " + parts[1] + "  (" + parts[2] + " of " + parts[3] + ")…"
}

// ------------------------------------------------------------ the launcher

// What the launcher said on stderr, as one line for the panel: its first,
// without the "arcade-launcher: " every message starts with.
function launcherError(text) {
  return String(text || "").trim().split("\n")[0].replace(/^arcade-launcher: /, "")
}

// --------------------------------------------------------- time and counts

// "2 hours ago", for the line under a tile. Coarse on purpose: when you last
// played Galaga is a feeling, not a timestamp.
function playedAgo(epoch, now) {
  if (!epoch) return ""
  var seconds = Math.max(0, Math.floor(now) - epoch)
  var minutes = Math.floor(seconds / 60)
  var hours = Math.floor(minutes / 60)
  var days = Math.floor(hours / 24)

  function plural(n, unit) { return n + " " + unit + (n === 1 ? "" : "s") + " ago" }
  if (minutes < 1) return "just now"
  if (hours < 1) return plural(minutes, "minute")
  if (days < 1) return plural(hours, "hour")
  if (days < 2) return "yesterday"
  if (days < 14) return plural(days, "day")
  if (days < 60) return plural(Math.floor(days / 7), "week")
  if (days < 730) return plural(Math.floor(days / 30), "month")
  return plural(Math.floor(days / 365), "year")
}

// What the line under a tile says after the ROM name.
// It speaks to the order the wall is in: plays when sorted by them, the year
// when sorted by that, otherwise when you last played it.
function tileNote(game, now, sort, paused) {
  if (!game) return ""
  var notes = []
  var plays = Library.playCount(game)
  if (sort === "most played" && plays) notes.push(plays === 1 ? "1 play" : plays + " plays")
  if (sort === "year" && game.year) notes.push(game.year)
  // Why it won't start, first: nothing else about it matters until it does.
  if (game.installed === false) return "not in your collection"
  if (Library.problemOf(game)) return "won't start  ·  " + Library.problemOf(game)
  if (Library.versionCount(game) > 1) notes.push((game.versionIndex + 1) + " of " + Library.versionCount(game) + " versions")
  if (game.playing) notes.push(paused ? "waiting for you" : "playing now")
  else if (Library.latestPlay(game) && sort !== "most played" && sort !== "year") notes.push(playedAgo(Library.latestPlay(game), now))
  return notes.join("  ·  ")
}

// The footer's word on a game with several versions, when there is nothing
// more pressing to say.
function versionNote(tile) {
  var n = Library.versionCount(tile)
  if (n < 2) return ""
  return n === 2 ? "Tab for the other version" : "Tab for the other " + (n - 1) + " versions"
}

// What Enter will do to the game already running, said before it is pressed.
function launchNote(selected, playing, paused) {
  if (!selected || !playing) return ""
  if (selected.path === playing.path)
    return paused ? "waiting for you · Enter picks it up where it was" : "playing now · Enter goes back to it"
  return "Enter closes " + playing.title + " and starts this"
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
