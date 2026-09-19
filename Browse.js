.pragma library
.import "Library.js" as Library

// The wall's order and what is on it: the sorts, the Show choice and the
// filters, moving the selection around the grid, and attract mode's order.
// Pure, like the rest, so test.js checks it.

// ----------------------------------------------------------------- sorting

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

function sortGames(games, sort) {
  var key = sortKey(sort)
  var list = (games || []).map(function(game, order) { return { game: game, order: order } })
  function compare(a, b) {
    var ga = a.game, gb = b.game
    if (key === "last played") {
      var la = Library.latestPlay(ga), lb = Library.latestPlay(gb)
      if (la !== lb) return lb - la
    } else if (key === "favourites") {
      var fa = Library.isFavourite(ga) ? 0 : 1, fb = Library.isFavourite(gb) ? 0 : 1
      if (fa !== fb) return fa - fb
    } else if (key === "most played") {
      var pa = Library.playCount(ga), pb = Library.playCount(gb)
      if (pa !== pb) return pb - pa
      var ra = Library.latestPlay(ga), rb = Library.latestPlay(gb)
      if (ra !== rb) return rb - ra
    } else if (key === "year") {
      // Oldest first, the way an arcade's history runs; no year at the end.
      var ya = Library.yearOf(ga) || (Library.decadeOf(ga) ? parseInt(Library.decadeOf(ga), 10) + 9.5 : 99999)
      var yb = Library.yearOf(gb) || (Library.decadeOf(gb) ? parseInt(Library.decadeOf(gb), 10) + 9.5 : 99999)
      if (ya !== yb) return ya - yb
    }
    return a.order - b.order
  }
  list.sort(compare)
  return list.map(function(e) { return e.game })
}

// ------------------------------------------------------------- which games

// The filters, each a chip that cycles: which games, which decade, which
// maker. "" is "any" for the last two. Decades and makers are only the ones
// the library actually has, so no choice ever shows an empty wall.
var SHOWS = [
  { key: "all", label: "In your collection" },
  { key: "favourites", label: "Favourites" },
  { key: "played", label: "Played" },
  { key: "unplayed", label: "Never played" },
  { key: "broken", label: "Won't start" },
  { key: "missing", label: "Not in your collection" },
  { key: "everything", label: "Every game" }
]

// Whether a game is in view at all for a Show choice, before any other
// filter: your own games, bar a few choices that reach past them.
function inScope(game, show) {
  if (show === "everything" || show === "favourites") return true
  if (show === "missing") return game.installed === false
  return game.installed !== false
}

// Show choices that need FinalBurn Neo's whole list, not just your games.
function needsCatalogue(show) {
  return show === "missing" || show === "everything"
}

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
    var d = Library.decadeOf(list[i])
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

// The kinds of game the library has, the commonest first. A game of two
// kinds counts for both.
function genreOptions(games) {
  var count = {}
  var names = []
  var list = games || []
  for (var i = 0; i < list.length; i++) {
    var gs = list[i].genres || []
    for (var j = 0; j < gs.length; j++) {
      if (!count[gs[j]]) { count[gs[j]] = 0; names.push(gs[j]) }
      count[gs[j]]++
    }
  }
  names.sort(function(a, b) { return count[b] !== count[a] ? count[b] - count[a] : (a < b ? -1 : 1) })
  return [""].concat(names)
}

// How many can play at once, as the library has it: "1", "2", "4"...
function playerOptions(games) {
  var seen = {}
  var out = []
  var list = games || []
  for (var i = 0; i < list.length; i++) {
    var n = list[i].players
    if (n > 0 && !seen[n]) { seen[n] = true; out.push(n) }
  }
  out.sort(function(a, b) { return a - b })
  return [""].concat(out.map(String))
}

function matchesFilters(game, filters) {
  var f = filters || ({})
  if (!inScope(game, f.show || "all")) return false
  if (f.show === "broken" && !Library.problemOf(game)) return false
  if (f.genre && (game.genres || []).indexOf(f.genre) < 0) return false
  if (f.players && String(game.players) !== String(f.players)) return false
  if (f.show === "favourites" && !Library.isFavourite(game)) return false
  if (f.show === "played" && !Library.latestPlay(game)) return false
  if (f.show === "unplayed" && Library.latestPlay(game)) return false
  if (f.decade && Library.decadeOf(game) !== f.decade) return false
  if (f.maker && game.maker !== f.maker) return false
  return true
}

function applyFilters(games, filters) {
  return (games || []).filter(function(g) { return matchesFilters(g, filters) })
}

function filtersActive(filters) {
  var f = filters || ({})
  return !!((f.show && f.show !== "all") || f.decade || f.maker || f.genre || f.players)
}

// The next value of one filter, as a new filters object. A filter whose
// value is no longer offered (the last Konami game was removed) starts over.
function stepFilter(filters, which, options, delta) {
  var next = {}
  for (var k in (filters || ({}))) next[k] = filters[k]
  next[which] = cycleOption(options, next[which] === undefined ? options[0] : next[which], delta)
  return next
}

// ----------------------------------------------------------- moving around

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

// ------------------------------------------------------------ attract mode

// The games attract mode can show: the ones whose title screen is here, in an
// order shuffled by `seed` -- a different run each time, but the same one for
// the same seed, so the tests can say what it is.
function attractOrder(games, map, seed) {
  var list = []
  var src = games || []
  for (var i = 0; i < src.length; i++) if (Library.artFor(map, src[i])) list.push(src[i])
  var s = (seed | 0) || 1
  function next() { s = (s * 1103515245 + 12345) & 0x7fffffff; return s / 0x80000000 }
  for (var j = list.length - 1; j > 0; j--) {
    var k = Math.floor(next() * (j + 1))
    var t = list[j]; list[j] = list[k]; list[k] = t
  }
  return list
}

// Seconds of quiet before attract mode starts, or 0 for never.
function attractSeconds(value) {
  var n = parseInt(String(value || ""), 10)
  return isNaN(n) || n <= 0 ? 0 : n
}

// ------------------------------------------------------------- small steps

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

function cycleOption(options, value, delta) {
  var list = options || []
  if (list.length === 0) return value
  var at = list.indexOf(value)
  if (at < 0) at = 0
  return list[((at + delta) % list.length + list.length) % list.length]
}
