.pragma library

// Pure logic for the arcade overlay: parsing what `arcade-launcher --list`
// prints, filtering it as you type, and the small formatting decisions the
// panel makes. Its siblings hold the rest -- Settings.js the editors,
// Controls.js the key names and binds, Pad.js the stick. None of it needs a
// running shell, so all of it is tested by test.js.

// "Title<TAB>/path/to/rom.zip<TAB>last played<TAB>playing<TAB>database title
// <TAB>year<TAB>maker<TAB>favourite<TAB>plays" per line, exactly what --list
// prints; all but the first two may be empty or absent. Lines without a
// tab are ignored rather than guessed at: a half-parsed row would launch the
// wrong file.
function parseList(text) {
  var games = []
  if (!text) return games

  var lines = String(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length < 2) continue

    var title = parts[0]
    var path = parts[1]
    if (!title.length || !path.length) continue

    var played = parseInt(parts[2] || "", 10)
    var plays = parseInt(parts[8] || "", 10)
    games.push({
      title: title, path: path, rom: romName(path),
      lastPlayed: isNaN(played) ? 0 : played,
      playing: parts[3] === "playing",
      dbTitle: parts[4] || "",
      year: parts[5] || "",
      maker: parts[6] || "",
      favourite: parts[7] === "favourite",
      plays: isNaN(plays) ? 0 : plays
    })
  }
  return games
}

// ------------------------------------------------------------------ versions
//
// A romset library holds the same game several times over: sfiii, sfiiiu and
// sfiiij are Street Fighter III for Europe, the USA and Japan. There is no
// parent/clone table on this machine to ask, but the database names every
// version of a game the same way with its differences in brackets, so the
// title with the brackets taken off is the game.

function versionKey(game) {
  if (!game) return ""
  var title = String(game.dbTitle || "")
  // No database title means nothing is known about it: it stands alone rather
  // than being lumped in by a guess.
  if (!title) return "rom:" + game.rom
  var base = title
  var before
  do {
    before = base
    base = base.replace(/\s*[\(\[][^\(\)\[\]]*[\)\]]\s*$/, "")
  } while (base !== before)
  // Letters and digits only: MAME's database writes "Nick _ Tom" where
  // FBNeo's writes "Nick & Tom", and punctuation is no way to tell games apart.
  base = base.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim()
  return base ? "title:" + base : "rom:" + game.rom
}

// Which version stands for the game when nobody has picked one. The parent set
// has the shortest name nearly always -- sfiii before sfiiiu -- which is also
// the one most people mean. MAME squeezes names into eight letters, though, so
// snowbros, snowbroa and snowbroj tie; then a set with a title of its own
// wins (the shipped titles name parents), then one the database calls
// "set 1" or "World", then the alphabet.
function mainVersion(versions) {
  function rank(v) {
    var db = String(v.dbTitle || "").toLowerCase()
    if (v.dbTitle && v.title !== v.dbTitle) return 0
    if (/\((set 1|world)\b/.test(db)) return 1
    return 2
  }
  var best = null
  for (var i = 0; i < versions.length; i++) {
    var v = versions[i]
    if (!best) { best = v; continue }
    if (v.rom.length !== best.rom.length) { if (v.rom.length < best.rom.length) best = v; continue }
    var rv = rank(v), rb = rank(best)
    if (rv < rb || (rv === rb && v.rom < best.rom)) best = v
  }
  return best
}

// One tile per game. The version a tile stands for is, in order: the one
// picked with Tab, the one running, the one played last, the main version.
// Each carries its siblings, main version first, so Tab can step through them.
function groupGames(games, picked) {
  var list = games || []
  var chosen = picked || ({})
  var order = []
  var groups = ({})

  for (var i = 0; i < list.length; i++) {
    var key = versionKey(list[i])
    if (!groups[key]) { groups[key] = []; order.push(key) }
    groups[key].push(list[i])
  }

  var out = []
  for (var g = 0; g < order.length; g++) {
    var members = groups[order[g]]
    var main = mainVersion(members)
    var versions = [main]
    for (var m = 0; m < members.length; m++) {
      if (members[m] !== main) versions.push(members[m])
    }

    var rep = null
    for (var a = 0; a < versions.length && !rep; a++) {
      if (versions[a].path === chosen[order[g]]) rep = versions[a]
    }
    for (var b = 0; b < versions.length && !rep; b++) {
      if (versions[b].playing) rep = versions[b]
    }
    if (!rep) {
      for (var c = 0; c < versions.length; c++) {
        if (versions[c].lastPlayed > 0 && (!rep || versions[c].lastPlayed > rep.lastPlayed)) rep = versions[c]
      }
    }
    if (!rep) rep = main

    var tile = {}
    for (var prop in rep) tile[prop] = rep[prop]
    tile.groupKey = order[g]
    // A game is a favourite whichever of its versions was marked: that
    // belongs to the game, not to the region it was marked in.
    tile.favourite = false
    for (var f = 0; f < versions.length; f++) if (versions[f].favourite) tile.favourite = true
    tile.versions = versions
    tile.versionIndex = versions.indexOf(rep)
    out.push(tile)
  }
  return out
}

// The next version of a tile's game, as the new picked map.
function stepVersion(picked, tile, delta) {
  var next = {}
  for (var key in (picked || ({}))) next[key] = picked[key]
  if (!tile || !tile.versions || tile.versions.length < 2) return next
  var n = tile.versions.length
  var at = ((tile.versionIndex + delta) % n + n) % n
  next[tile.groupKey] = tile.versions[at].path
  return next
}

function versionCount(tile) {
  return tile && tile.versions ? tile.versions.length : 1
}

// ------------------------------------------------------ sorting and filters
//
// One wall, in whichever order was picked. With nothing typed it is "last
// played" by default, so opening the panel and pressing Enter replays the
// last game. The launcher lists the library alphabetically, so that order is
// the tie-breaker everywhere and "name" is the list as it comes.

var SORTS = [
  { key: "last played", label: "Last played" },
  { key: "favourites", label: "Favourites" },
  { key: "most played", label: "Most played" },
  { key: "name", label: "Name" },
  { key: "year", label: "Year" }
]

function sortKeys() {
  return SORTS.map(function(s) { return s.key })
}

// An unknown sort -- a typo in arcade.conf -- is the default, not an error.
function sortKey(value) {
  var v = String(value || "").trim().toLowerCase()
  return sortKeys().indexOf(v) >= 0 ? v : "last played"
}

function sortLabel(key) {
  for (var i = 0; i < SORTS.length; i++) if (SORTS[i].key === key) return SORTS[i].label
  return SORTS[0].label
}

// A tile stands for every version of its game: it was last played when any
// of them was, and its plays are all of theirs.
function latestPlay(game) {
  if (!game) return 0
  var versions = game.versions || [game]
  var latest = 0
  for (var i = 0; i < versions.length; i++) latest = Math.max(latest, versions[i].lastPlayed || 0)
  return latest
}

function playCount(game) {
  if (!game) return 0
  var versions = game.versions || [game]
  var n = 0
  for (var i = 0; i < versions.length; i++) n += versions[i].plays || 0
  return n
}

// "1987" and "1987?" are 1987; "198?" is known only to the decade.
function yearOf(game) {
  var m = /^(\d{4})/.exec(String(game && game.year || ""))
  return m ? parseInt(m[1], 10) : 0
}

function decadeOf(game) {
  var m = /^(\d{3})/.exec(String(game && game.year || ""))
  return m ? m[1] + "0s" : ""
}

function sortGames(games, sort) {
  var key = sortKey(sort)
  var list = (games || []).map(function(game, order) { return { game: game, order: order } })
  function compare(a, b) {
    var ga = a.game, gb = b.game
    if (key === "last played") {
      var la = latestPlay(ga), lb = latestPlay(gb)
      if (la !== lb) return lb - la
    } else if (key === "favourites") {
      var fa = isFavourite(ga) ? 0 : 1, fb = isFavourite(gb) ? 0 : 1
      if (fa !== fb) return fa - fb
    } else if (key === "most played") {
      var pa = playCount(ga), pb = playCount(gb)
      if (pa !== pb) return pb - pa
      var ra = latestPlay(ga), rb = latestPlay(gb)
      if (ra !== rb) return rb - ra
    } else if (key === "year") {
      // Oldest first, the way an arcade's history runs; no year at the end.
      var ya = yearOf(ga) || (decadeOf(ga) ? parseInt(decadeOf(ga), 10) + 9.5 : 99999)
      var yb = yearOf(gb) || (decadeOf(gb) ? parseInt(decadeOf(gb), 10) + 9.5 : 99999)
      if (ya !== yb) return ya - yb
    }
    return a.order - b.order
  }
  list.sort(compare)
  return list.map(function(e) { return e.game })
}

// The filters, each a chip that cycles: which games, which decade, which
// maker. "" is "any" for the last two. Decades and makers are only the ones
// the library actually has, so no choice ever shows an empty wall.
var SHOWS = [
  { key: "all", label: "All games" },
  { key: "favourites", label: "Favourites" },
  { key: "played", label: "Played" },
  { key: "unplayed", label: "Never played" }
]

function showKeys() {
  return SHOWS.map(function(s) { return s.key })
}

function showLabel(key) {
  for (var i = 0; i < SHOWS.length; i++) if (SHOWS[i].key === key) return SHOWS[i].label
  return SHOWS[0].label
}

function decadeOptions(games) {
  var seen = {}
  var out = []
  var list = games || []
  for (var i = 0; i < list.length; i++) {
    var d = decadeOf(list[i])
    if (d && !seen[d]) { seen[d] = true; out.push(d) }
  }
  out.sort()
  return [""].concat(out)
}

// Makers with the most games first: that is who you are likely looking for,
// and the one-offs can wait at the end of the cycle.
function makerOptions(games) {
  var count = {}
  var names = []
  var list = games || []
  for (var i = 0; i < list.length; i++) {
    var m = String(list[i].maker || "")
    if (!m) continue
    if (!count[m]) { count[m] = 0; names.push(m) }
    count[m]++
  }
  names.sort(function(a, b) { return count[b] !== count[a] ? count[b] - count[a] : (a.toLowerCase() < b.toLowerCase() ? -1 : 1) })
  return [""].concat(names)
}

function matchesFilters(game, filters) {
  var f = filters || ({})
  if (f.show === "favourites" && !isFavourite(game)) return false
  if (f.show === "played" && !latestPlay(game)) return false
  if (f.show === "unplayed" && latestPlay(game)) return false
  if (f.decade && decadeOf(game) !== f.decade) return false
  if (f.maker && game.maker !== f.maker) return false
  return true
}

function applyFilters(games, filters) {
  return (games || []).filter(function(g) { return matchesFilters(g, filters) })
}

function filtersActive(filters) {
  var f = filters || ({})
  return !!((f.show && f.show !== "all") || f.decade || f.maker)
}

// The next value of one filter, as a new filters object. A filter whose
// value is no longer offered (the last Konami game was removed) starts over.
function stepFilter(filters, which, options, delta) {
  var next = {}
  for (var k in (filters || ({}))) next[k] = filters[k]
  next[which] = cycleOption(options, next[which] === undefined ? options[0] : next[which], delta)
  return next
}

// What the empty wall says when the filters leave nothing.
function emptyNote(filters) {
  var f = filters || ({})
  if (f.show === "favourites" && !f.decade && !f.maker) return "No favourites yet. Alt+F on a game adds it."
  if (f.show === "unplayed" && !f.decade && !f.maker) return "You have played every game here."
  return "No games match these filters."
}

// Whether a game (or any version of a tile) is a favourite.
function isFavourite(game) {
  if (!game) return false
  if (game.favourite) return true
  var versions = game.versions || []
  for (var i = 0; i < versions.length; i++) if (versions[i].favourite) return true
  return false
}

// The launcher arguments that make a game a favourite or not. Taking it off
// clears every version, since any one of them makes the tile a favourite;
// adding it marks the version showing.
function favouriteArgs(game) {
  if (!game || !game.rom) return []
  if (!isFavourite(game)) return ["--favourite", game.rom]
  var roms = []
  var versions = game.versions && game.versions.length ? game.versions : [game]
  for (var i = 0; i < versions.length; i++) {
    if (versions[i].favourite && roms.indexOf(versions[i].rom) < 0) roms.push(versions[i].rom)
  }
  return ["--unfavourite"].concat(roms)
}

// Where the selection goes. The first `recent` games sit on a shelf of their
// own above the wall, so up from the wall's first row lands on the shelf, and
// down from the shelf lands on the wall's first row, in the nearest column.
// Left and right simply run on through the list.
function wallMove(index, action, columns, recent, total) {
  if (total <= 0) return 0
  var cols = Math.max(1, columns | 0)
  var shelf = Math.max(0, Math.min(recent | 0, total))
  var wall = total - shelf
  var at = clampIndex(index, total)

  if (action === "left") return clampIndex(at - 1, total)
  if (action === "right") return clampIndex(at + 1, total)
  if (action === "page-down") return wallMove(wallMove(at, "down", cols, shelf, total), "down", cols, shelf, total)
  if (action === "page-up") return wallMove(wallMove(at, "up", cols, shelf, total), "up", cols, shelf, total)

  if (at < shelf) {
    if (action === "down") return wall > 0 ? shelf + Math.min(at, wall - 1) : at
    return at
  }
  var place = at - shelf
  if (action === "up") {
    if (place >= cols) return at - cols
    return shelf > 0 ? Math.min(place, shelf - 1) : at
  }
  if (action === "down") {
    // Down from the next-to-last row lands on the last one even when it is
    // short, rather than refusing because the column below is empty.
    if (place + cols < wall) return at + cols
    return Math.floor(place / cols) < Math.floor((wall - 1) / cols) ? total - 1 : at
  }
  return at
}

// The line under the selected game's name: who made it and when, how many
// versions there are, and when it was last played.
function gameFacts(game, now) {
  if (!game) return ""
  var facts = []
  if (game.maker) facts.push(game.maker)
  if (game.year) facts.push(game.year)
  if (versionCount(game) > 1) facts.push(versionCount(game) + " versions")
  if (game.playing) facts.push("playing now")
  else if (latestPlay(game)) facts.push("played " + playedAgo(latestPlay(game), now))
  var plays = playCount(game)
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
    if (parts[0] === "added") added.push(romName(parts[1]))
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

// What the launcher said on stderr, as one line for the panel: its first,
// without the "arcade-launcher: " every message starts with.
function launcherError(text) {
  return String(text || "").trim().split("\n")[0].replace(/^arcade-launcher: /, "")
}

// Dropped URLs as local paths; anything not a local file is left out.
function droppedPaths(urls) {
  var out = []
  var list = urls || []
  for (var i = 0; i < list.length; i++) {
    var url = String(list[i])
    if (url.indexOf("file://") !== 0) continue
    out.push(decodeURIComponent(url.substring("file://".length)))
  }
  return out
}

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
function tileNote(game, now, sort) {
  if (!game) return ""
  var notes = []
  var plays = playCount(game)
  if (sort === "most played" && plays) notes.push(plays === 1 ? "1 play" : plays + " plays")
  if (sort === "year" && game.year) notes.push(game.year)
  if (versionCount(game) > 1) notes.push((game.versionIndex + 1) + " of " + versionCount(game) + " versions")
  if (game.playing) notes.push("playing now")
  else if (latestPlay(game) && sort !== "most played" && sort !== "year") notes.push(playedAgo(latestPlay(game), now))
  return notes.join("  ·  ")
}

// The footer's word on a game with several versions, when there is nothing
// more pressing to say.
function versionNote(tile) {
  var n = versionCount(tile)
  if (n < 2) return ""
  return n === 2 ? "Tab for the other version" : "Tab for the other " + (n - 1) + " versions"
}

function playingGame(games) {
  var list = games || []
  for (var i = 0; i < list.length; i++) {
    if (list[i].playing) return list[i]
  }
  return null
}

// What Enter will do to the game already running, said before it is pressed.
function launchNote(selected, playing) {
  if (!selected || !playing) return ""
  if (selected.path === playing.path) return "playing now · Enter goes back to it"
  return "Enter closes " + playing.title + " and starts this"
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

function cycleOption(options, value, delta) {
  var list = options || []
  if (list.length === 0) return value
  var at = list.indexOf(value)
  if (at < 0) at = 0
  return list[((at + delta) % list.length + list.length) % list.length]
}
