.pragma library

// Pure logic for the arcade overlay: the games themselves -- parsing what
// `arcade-launcher --list` prints, grouping versions, what is known about a
// game, searching as you type, its artwork. Its siblings hold the rest:
// Browse.js the wall's order and filters, Present.js what the panel says,
// Settings.js the editors, Controls.js the key names and binds, Pad.js the
// stick. None of it needs a running shell, so all of it is tested by test.js.

// "Title<TAB>/path/to/rom.zip<TAB>last played<TAB>playing<TAB>database title
// <TAB>year<TAB>maker<TAB>favourite<TAB>plays<TAB>genre<TAB>players
// <TAB>orientation<TAB>problem<TAB>family<TAB>missing" per line, exactly what
// --list prints; all but the first two may be empty or absent. Lines without a
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
      plays: isNaN(plays) ? 0 : plays,
      // "Maze / Action": a game can be more than one kind.
      genres: parts[9] ? parts[9].split(" / ") : [],
      players: parseInt(parts[10] || "", 10) || 0,
      vertical: parts[11] === "vertical",
      // Why it does not start, as last found out; "" when it does or nobody knows.
      problem: parts[12] || "",
      // The parent set this one is a version of, itself for a parent -- from
      // FinalBurn Neo's own table; "" when FBNeo does not know the game.
      family: parts[13] || "",
      // A game FinalBurn Neo knows that is not in ROM_DIR: its "path" is the
      // bare ROM name, and it can be browsed and made a favourite, not played.
      installed: parts[14] !== "missing"
    })
  }
  return games
}

// A romset library holds the same game several times over: sfiii, sfiiiu and
// sfiiij are Street Fighter III for Europe, the USA and Japan. FinalBurn
// Neo's table says which set each is a version of, and that is the answer
// wherever it knows the game. For the rest, the database names every version
// of a game the same way with its differences in brackets, so the title with
// the brackets taken off is the game.

// ---------------------------------------------------------------- versions

function versionKey(game) {
  if (!game) return ""
  if (game.family) return "set:" + game.family
  return titleKey(game)
}

function titleKey(game) {
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

// Which version stands for the game when nobody has picked one: the parent
// set, when FinalBurn Neo says which that is. Otherwise the parent has the
// shortest name nearly always -- sfiii before sfiiiu -- which is also the one
// most people mean. MAME squeezes names into eight letters, though, so
// snowbros, snowbroa and snowbroj tie; then a set with a title of its own
// wins (the shipped titles name parents), then one the database calls
// "set 1" or "World", then the alphabet.
function mainVersion(versions) {
  function parent(v) { return !!v.family && v.rom === v.family }
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
    if (parent(v) !== parent(best)) { if (parent(v)) best = v; continue }
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

  // A version FBNeo does not know (a MAME-only set, say) joins the family of
  // one it does know by the same title, rather than standing apart from its
  // own siblings.
  var families = ({})
  for (var f = 0; f < list.length; f++) {
    if (!list[f].family || !list[f].dbTitle) continue
    var tk = titleKey(list[f])
    if (!families[tk]) families[tk] = versionKey(list[f])
  }

  for (var i = 0; i < list.length; i++) {
    var key = versionKey(list[i])
    if (!list[i].family && families[key]) key = families[key]
    if (!groups[key]) { groups[key] = []; order.push(key) }
    groups[key].push(list[i])
  }

  var out = []
  for (var g = 0; g < order.length; g++) {
    var members = groups[order[g]]
    // What you have stands for the game; the versions you do not have only
    // count when you have none of them.
    var owned = members.filter(function(v) { return v.installed !== false })
    var missing = members.length - owned.length
    if (owned.length) members = owned
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
    tile.installed = owned.length > 0
    tile.missingVersions = owned.length ? missing : 0
    // A game is a favourite whichever of its versions was marked: that
    // belongs to the game, not to the region it was marked in.
    tile.favourite = false
    for (var f = 0; f < versions.length; f++) if (versions[f].favourite) tile.favourite = true
    tile.versions = versions
    tile.versionIndex = versions.indexOf(rep)
    out.push(tile)
  }
  // Each tile where its main version is in the list -- the launcher's list
  // is in title order -- so a family is listed by its parent's name, not by
  // whichever version's name came first ("Tournament Pro Golf" among the T's,
  // not beside "18 Holes Pro Golf"). The main version, not the one showing,
  // so stepping through versions never moves the tile.
  var place = new Map()
  for (var p = 0; p < list.length; p++) place.set(list[p], p)
  var at = out.map(function(t) { return { t: t, n: place.get(t.versions[0]) } })
  at.sort(function(a, b) { return a.n - b.n })
  return at.map(function(e) { return e.t })
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

// One wall, in whichever order was picked. With nothing typed it is "last
// played" by default, so opening the panel and pressing Enter replays the
// last game. The launcher lists the library alphabetically, so that order is
// the tie-breaker everywhere and "name" is the list as it comes.

// ---------------------------------------------- what is known about a game

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

// A tile stands for all its versions: it won't start only if the one showing
// won't -- another version may be the one that works.
function problemOf(game) {
  return game ? String(game.problem || "") : ""
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

// --------------------------------------------------------- files and names

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

function playingGame(games) {
  var list = games || []
  for (var i = 0; i < list.length; i++) {
    if (list[i].playing) return list[i]
  }
  return null
}

function romName(path) {
  var base = String(path).replace(/^.*\//, "")
  return base.replace(/\.[^.]*$/, "")
}

// ------------------------------------------------------------------ search

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

// ----------------------------------------------------------------- artwork

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
