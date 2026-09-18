.pragma library

// Pure logic for the arcade overlay: parsing what `arcade-launcher --list`
// prints, filtering it as you type, and the small formatting decisions the
// panel makes. None of it needs a running shell, so all of it is tested by
// test.js.

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

// The stick's name for the button that makes a game a favourite: the first of ZR/ZL
// (RetroPad R2, L2) its profile binds, or "".
function favouriteStickKey(controller) {
  return padLabel(controller, "r2") || padLabel(controller, "l2")
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
function gameRows(parsed) {
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

  var controls = controlsSchema()
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
  if (row.layout) return layoutLabel(row.value)
  return describeBind(row.value)
}
