#!/usr/bin/env node
// Unit tests for the panel's logic: Library.js, Browse.js, Present.js,
// Controls.js, Settings.js, Pad.js.
//
//     node test.js        # prints every failure, exits 1 if any
//
// Library.js owns the parsing and the match ranking -- the parts that decide
// which ROM Enter launches. Getting that wrong starts the wrong game, so it is
// checked here rather than by playing.
//
// The modules are loaded by evaluating them, minus the QML `.pragma library`
// and `.import` lines node cannot parse, with each one's imports handed in as
// the module objects already loaded. Every check sees them merged into one M.
const fs = require("fs")
const path = require("path")

const MODULES = ["Library", "Browse", "Present", "Controls", "Settings", "Pad"]

function loadModules() {
  const loaded = {}
  for (const name of MODULES) {
    const raw = fs.readFileSync(path.join(__dirname, name + ".js"), "utf8")
    const imports = [...raw.matchAll(/^\s*\.import\s+"(\w+)\.js"\s+as\s+(\w+)\s*$/gm)].map((m) => m[2])
    const src = raw.replace(/^\s*\.(pragma|import)\b.*$/gm, "")
    const names = []
    for (const m of src.matchAll(/^(?:function|var)\s+([A-Za-z_$][\w$]*)/gm)) names.push(m[1])
    loaded[name] = new Function(...imports, src + "\nreturn {" + names.join(", ") + "}")(...imports.map((i) => loaded[i]))
  }
  return Object.assign({}, ...MODULES.map((n) => loaded[n]))
}

const M = loadModules()
const HOME = "/home/kimm"
let checks = 0
const failures = []

function check(label, got, want) {
  checks += 1
  const g = JSON.stringify(got), w = JSON.stringify(want)
  if (g !== w) failures.push(`${label}\n      got  ${g}\n      want ${w}`)
}

const LIST = [
  "Bubble Bobble\t/home/kimm/Games/roms/bublbobl.zip",
  "Pang\t/home/kimm/Games/roms/pang.zip",
  "Snow Bros. 2: With New Elves\t/home/kimm/Games/roms/snowbro2.zip",
  "Snow Bros.: Nick & Tom\t/home/kimm/Games/roms/snowbros.zip",
  "Super Pang\t/home/kimm/Games/roms/spang.zip",
  "Wonder Boy in Monster Land\t/home/kimm/Games/roms/wbml.zip",
].join("\n")

const games = M.parseList(LIST)
const titles = list => list.map(g => g.title)

// ------------------------------------------------------------------ parsing

check("every row is read", games.length, 6)
check("title is the first field", games[0].title, "Bubble Bobble")
check("path is the second", games[0].path, "/home/kimm/Games/roms/bublbobl.zip")
check("a game never played has no date", games[0].lastPlayed, 0)
check("rom name comes off the path", games[0].rom, "bublbobl")
check("a title may contain a colon", games[2].title, "Snow Bros. 2: With New Elves")
check("nothing parses to nothing", M.parseList(""), [])
check("trailing newline adds no row", M.parseList("A\t/a.zip\n").length, 1)
// A row with no tab cannot say which file it would launch.
check("a row without a tab is dropped", M.parseList("just a title").length, 0)
check("an empty path is dropped", M.parseList("Title\t").length, 0)

// ------------------------------------------------------------------ history

const PLAYED = M.parseList([
  "Bubble Bobble\t/r/bublbobl.zip\t1000\t",
  "Galaga\t/r/galaga.zip\t\t",
  "Pang\t/r/pang.zip\t3000\tplaying",
  "Rainbow Islands\t/r/rbisland.zip\t2000",
  "Toki\t/r/toki.zip",
].join("\n"))

check("when it was last played is read", PLAYED[0].lastPlayed, 1000)
check("the game running now is marked", PLAYED[2].playing, true)
check("and no other", PLAYED.filter(g => g.playing).length, 1)
check("the older two-column form still reads", PLAYED[4].path, "/r/toki.zip")

check("last played leads with the newest, then the alphabet",
      titles(M.sortGames(PLAYED, "last played")), ["Pang", "Rainbow Islands", "Bubble Bobble", "Galaga", "Toki"])
check("name keeps the alphabet", titles(M.sortGames(PLAYED, "name")), titles(PLAYED))
check("an unknown sort is last played", M.sortKey("sideways"), "last played")
check("a sort from the file is read loosely", M.sortKey(" Most Played "), "most played")
check("a library nobody has played is just the alphabet", titles(M.sortGames(games, "last played")), titles(games))

check("seconds ago is just now", M.playedAgo(1000, 1030), "just now")
check("one minute is singular", M.playedAgo(1000, 1000 + 60), "1 minute ago")
check("hours", M.playedAgo(0 + 1, 1 + 3 * 3600), "3 hours ago")
check("a day and a bit is yesterday", M.playedAgo(1, 1 + 30 * 3600), "yesterday")
check("days", M.playedAgo(1, 1 + 5 * 86400), "5 days ago")
check("weeks", M.playedAgo(1, 1 + 21 * 86400), "3 weeks ago")
check("months", M.playedAgo(1, 1 + 95 * 86400), "3 months ago")
check("never played says nothing", M.playedAgo(0, 5000), "")

check("the tile of the running game says so", M.tileNote(PLAYED[2], 4000), "playing now")
check("a played one says when", M.tileNote(PLAYED[0], 1000 + 7200), "2 hours ago")
check("the running game is found", M.playingGame(PLAYED).title, "Pang")
check("Enter on the running game goes back to it",
      M.launchNote(PLAYED[2], PLAYED[2]), "playing now · Enter goes back to it")
check("Enter on another replaces it, and says so first",
      M.launchNote(PLAYED[0], PLAYED[2]), "Enter closes Pang and starts this")
check("with nothing running Enter just plays", M.launchNote(PLAYED[0], null), "")

// -------------------------------------------------------------- the shelf

const PLAYED_META = M.parseList("Bubble Bobble\t/r/bublbobl.zip\t\t\tBubble Bobble (Japan, Ver 0.1)\t1986\tTaito")

check("year and maker are read", [PLAYED_META[0].year, PLAYED_META[0].maker], ["1986", "Taito"])

// A shelf of 3 over a wall of 10, 4 to a row: 3..6, 7..10, 11..12.
const mv = (i, a) => M.wallMove(i, a, 4, 3, 13)
check("down from the shelf lands in the same column of the wall", mv(1, "down"), 4)
check("up from the wall's first row lands on the shelf, same column", mv(4, "up"), 1)
check("from past the shelf's end, on its last game", mv(6, "up"), 2)
check("up the wall a row at a time", mv(9, "up"), 5)
check("down the wall a row at a time", mv(4, "down"), 8)
check("down onto a short last row lands on its end", mv(10, "down"), 12)
check("down from the last row stays", mv(12, "down"), 12)
check("up from the shelf stays", mv(0, "up"), 0)
check("right runs from the shelf onto the wall", mv(2, "right"), 3)
check("left runs back", mv(3, "left"), 2)
check("a page is two rows", mv(4, "page-down"), 12)
check("without a shelf, up from the first row stays", M.wallMove(2, "up", 4, 0, 10), 2)

// ------------------------------------------------ favourites, sorts, filters

const LIB = M.parseList([
  "Bubble Bobble\t/r/bublbobl.zip\t1000\t\tBubble Bobble\t1986\tTaito\tfavourite\t9",
  "Galaga\t/r/galaga.zip\t\t\tGalaga\t1981\tNamco\tfavourite",
  "Pang\t/r/pang.zip\t3000\t\tPang\t1989\tMitchell\t\t2",
  "Rainbow Islands\t/r/rbisland.zip\t\t\tRainbow Islands\t1987\tTaito",
  "Toki\t/r/toki.zip\t2000\t\tToki\t198?\tTAD\tfavourite\t2",
  "Mystery\t/r/mystery.zip",
].join("\n"))
check("a favourite and its plays are read", [LIB[0].favourite, LIB[0].plays, LIB[3].favourite, LIB[3].plays],
      [true, 9, false, 0])
check("favourites first, each part alphabetical",
      titles(M.sortGames(LIB, "favourites")), ["Bubble Bobble", "Galaga", "Toki", "Pang", "Rainbow Islands", "Mystery"])
check("most played; a tie goes to the one played last",
      titles(M.sortGames(LIB, "most played")), ["Bubble Bobble", "Pang", "Toki", "Galaga", "Rainbow Islands", "Mystery"])
check("year, oldest first; a decade alone after its years, none at the end",
      titles(M.sortGames(LIB, "year")), ["Galaga", "Bubble Bobble", "Rainbow Islands", "Pang", "Toki", "Mystery"])

check("show favourites", titles(M.applyFilters(LIB, { show: "favourites" })), ["Bubble Bobble", "Galaga", "Toki"])
check("show played", titles(M.applyFilters(LIB, { show: "played" })), ["Bubble Bobble", "Pang", "Toki"])
check("show never played", titles(M.applyFilters(LIB, { show: "unplayed" })), ["Galaga", "Rainbow Islands", "Mystery"])
check("a decade", titles(M.applyFilters(LIB, { decade: "1980s" })).length, 5)
check("the decades the library has", M.decadeOptions(LIB), ["", "1980s"])
check("the makers, most games first", M.makerOptions(LIB), ["", "Taito", "Mitchell", "Namco", "TAD"])
check("filters combine", titles(M.applyFilters(LIB, { show: "favourites", maker: "Taito" })), ["Bubble Bobble"])
check("no filters, nothing active", M.filtersActive({ show: "all", decade: "", maker: "" }), false)
check("one is enough", M.filtersActive({ show: "all", maker: "Taito" }), true)
check("a filter steps on", M.stepFilter({ show: "all" }, "show", M.showKeys(), 1).show, "favourites")
check("and wraps back", M.stepFilter({ show: "all" }, "show", M.showKeys(), -1).show, "everything")
check("the empty wall says why", M.emptyNote({ show: "favourites" }), "No favourites yet. Alt+F on a game adds it.")

const STAR_SETS = M.groupGames(M.parseList([
  "Street Fighter III\t/r/sfiii.zip\t500\t\tStreet Fighter III (Europe 970204)\t\t\t\t3",
  "Street Fighter III\t/r/sfiiij.zip\t900\t\tStreet Fighter III (Japan 970204)\t\t\tfavourite\t4",
  "Toki\t/r/toki.zip\t\t\tToki (World)",
].join("\n")), { "title:street fighter iii": "/r/sfiii.zip" })
check("a game is a favourite when any version is", STAR_SETS[0].favourite, true)
check("whichever version is showing", STAR_SETS[0].rom, "sfiii")
check("its plays are all its versions'", M.playCount(STAR_SETS[0]), 7)
check("and it was last played when any of them was", M.latestPlay(STAR_SETS[0]), 900)
check("a game never played says nothing of plays", M.tileNote(STAR_SETS[1], 1000, "most played"), "")
check("unfavouriting takes it off the version that has it",
      M.favouriteArgs(STAR_SETS[0]), ["--unfavourite", "sfiiij"])
check("favouriting marks the version showing", M.favouriteArgs(STAR_SETS[1]), ["--favourite", "toki"])
check("nothing selected, nothing to do", M.favouriteArgs(null), [])
check("plays on the tile, sorted by them", M.tileNote(LIB[0], 1000, "most played"), "9 plays")
check("the year, sorted by it", M.tileNote(LIB[0], 1000, "year"), "1986")

check("ZL or ZR makes a favourite", [M.stickAction("l2", "wall"), M.stickAction("r2", "wall")], ["favourite", "favourite"])
check("the stick clicks sort and filter", [M.stickAction("l3", "wall"), M.stickAction("r3", "wall")], ["sort", "show"])
check("the stick's favourite key is its own name for it",
      M.favouriteStickKey({ binds: { r2: { spec: "8", label: "ZR" } } }), "ZR")
check("no trigger, no favourite key", M.favouriteStickKey({ binds: {} }), "")

check("the facts line", M.gameFacts(Object.assign({}, PLAYED_META[0], { lastPlayed: 1000 }), 1000 + 7200),
      "Taito  ·  1986  ·  played 2 hours ago  ·  bublbobl.zip")
check("keyboard hints", M.wallHints(false, false).map((h) => h.keys.join("+") + " " + h.label),
      ["Enter Play", "Alt+A Add", "Alt+S Settings", "Esc Close"])
check("keyboard hints with a game to favourite",
      M.wallHints(false, false, { on: false }).map((h) => h.keys.join("+") + " " + h.label),
      ["Enter Play", "Alt+F Favourite", "Alt+E Edit", "Alt+A Add", "Alt+S Settings", "Esc Close"])
check("and one to unfavourite, on the stick",
      M.wallHints(true, false, { on: true, stickKey: "ZR" }).map((h) => h.keys.join("+") + " " + h.label),
      ["B Play", "ZR Unfavourite", "− Settings", "Home Close"])
check("stick hints, with versions", M.wallHints(true, true).map((h) => h.keys.join("+") + " " + h.label),
      ["B Play", "Y+X Version", "− Settings", "Home Close"])

check("a launcher error is its first line, unprefixed",
      M.launcherError("arcade-launcher: no such file: /x\nmore detail\n"), "no such file: /x")
check("nothing said is nothing", M.launcherError(undefined), "")

// ---------------------------------------------------------------- families

const FAM = M.parseList([
  // FBNeo knows these three: two versions of Bubble Bobble, and Bubble Bobble
  // II, which is its own game even though its title starts the same way.
  "Bubble Bobble\t/r/bublboblu.zip\t\t\tBubble Bobble (US, Ver 5.1)\t\t\t\t\t\t\t\t\tbublbobl",
  "Bubble Bobble\t/r/bublbobl.zip\t\t\tBubble Bobble (Japan, Ver 0.1)\t\t\t\t\t\t\t\t\tbublbobl",
  "Bubble Bobble II\t/r/bublbob2.zip\t\t\tBubble Bobble II (Ver 2.6O 1994/12/16)\t\t\t\t\t\t\t\t\tbublbob2",
  // A MAME-only version FBNeo has no row for: it joins by its title.
  "Bubble Bobble\t/r/boblbobl.zip\t\t\tBubble Bobble (bootleg)",
  // Two sets FBNeo calls different games, however alike their titles.
  "Snow Bros.\t/r/snowbros.zip\t\t\tSnow Bros. - Nick & Tom (set 1)\t\t\t\t\t\t\t\t\tsnowbros",
  "Snow Bros.\t/r/snowbrox.zip\t\t\tSnow Bros. - Nick & Tom (set 2)\t\t\t\t\t\t\t\t\tsnowbrox",
].join("\n"))
check("the family is read", [FAM[0].family, FAM[3].family], ["bublbobl", ""])
const FAMT = M.groupGames(FAM)
check("versions group by FBNeo's family", FAMT.map((t) => t.versions.map((v) => v.rom)),
      [["bublbobl", "bublboblu", "boblbobl"], ["bublbob2"], ["snowbros"], ["snowbrox"]])
check("the parent set stands for the game", FAMT[0].rom, "bublbobl")
check("FBNeo's word beats a title that looks the same", FAMT.length, 4)

// --------------------------------------------------- beyond your collection

const CAT = M.parseList([
  "Bubble Bobble\t/r/bublbobl.zip\t\t\tBubble Bobble (Japan, Ver 0.1)\t1986\tTaito\t\t\tPlatform\t2\thorizontal\t\tbublbobl\t",
  "Bubble Bobble\tbublboblr\t\t\tBubble Bobble (US, Ver 5.1)\t1986\tTaito\t\t\tPlatform\t2\thorizontal\t\tbublbobl\tmissing",
  "Galaga\tgalaga\t\t\tGalaga (Namco rev. B)\t1981\tNamco\tfavourite\t\tVertical shooter\t2\tvertical\t\tgalaga\tmissing",
  "Galaga\tgalagao\t\t\tGalaga (Namco)\t1981\tNamco\t\t\tVertical shooter\t2\tvertical\t\tgalaga\tmissing",
].join("\n"))
check("a game you do not have is marked, and keeps its ROM name", [CAT[0].installed, CAT[1].installed, CAT[1].rom], [true, false, "bublboblr"])
const CATT = M.groupGames(CAT)
check("still one tile per game", CATT.map((t) => t.rom), ["bublbobl", "galaga"])
const ORDERED = M.groupGames(M.parseList([
  "18 Holes Pro Golf\tholes18\t\t\t\t\t\t\t\t\t\t\t\ttpgolf\tmissing",
  "Galaga\tgalaga\t\t\t\t\t\t\t\t\t\t\t\tgalaga\tmissing",
  "Tournament Pro Golf\ttpgolf\t\t\t\t\t\t\t\t\t\t\t\ttpgolf\tmissing",
].join("\n")))
check("a family is listed by the name its tile shows", titles(ORDERED), ["Galaga", "Tournament Pro Golf"])
check("your version stands for it, and Tab only steps through what you have",
      [CATT[0].installed, CATT[0].versions.map((v) => v.rom), CATT[0].missingVersions], [true, ["bublbobl"], 1])
check("a game you have none of shows all its versions", [CATT[1].installed, CATT[1].versions.length], [false, 2])
check("your collection is the default view", titles(M.applyFilters(CATT, { show: "all" })), ["Bubble Bobble"])
check("not in your collection", titles(M.applyFilters(CATT, { show: "missing" })), ["Galaga"])
check("every game", M.applyFilters(CATT, { show: "everything" }).length, 2)
check("a favourite you do not have yet is still a favourite", titles(M.applyFilters(CATT, { show: "favourites" })), ["Galaga"])
check("only the choices that reach past your games need FBNeo's list",
      M.showKeys().filter(M.needsCatalogue), ["missing", "everything"])
check("the footer says how to get it", M.problemNote(CATT[1]),
      "Not in your collection. FinalBurn Neo plays it as galaga.zip; Alt+A adds a romset")
check("and so does the tile", M.tileNote(CATT[1], 0, "last played"), "not in your collection")

// ------------------------------------------------------- facts and problems

const FACTS = M.parseList([
  "Bubble Bobble\t/r/bublbobl.zip\t\t\tBubble Bobble\t1986\tTaito\t\t\tPlatform\t2\thorizontal\t",
  "Ms. Pac-Man\t/r/mspacman.zip\t\t\tMs. Pac-Man\t1981\tMidway\t\t\tMaze / Action\t2\tvertical\t",
  "Metal Slug\t/r/mslug.zip\t\t\tMetal Slug\t1996\tNazca\t\t\tRun & gun\t2\thorizontal\t13 files are missing",
  "Gauntlet\t/r/gauntlet.zip\t\t\tGauntlet\t1985\tAtari\t\t\tMaze\t4\thorizontal\t",
  "Mystery\t/r/mystery.zip",
].join("\n"))
check("genre, players, screen and problem are read",
      [FACTS[1].genres, FACTS[1].players, FACTS[1].vertical, FACTS[2].problem], [["Maze", "Action"], 2, true, "13 files are missing"])
check("a romset nothing is known about has none of them",
      [FACTS[4].genres, FACTS[4].players, FACTS[4].vertical, FACTS[4].problem], [[], 0, false, ""])
check("the kinds of game, commonest first", M.genreOptions(FACTS), ["", "Maze", "Action", "Platform", "Run & gun"])
check("a game of two kinds is found under either", titles(M.applyFilters(FACTS, { genre: "Action" })), ["Ms. Pac-Man"])
check("the player counts the library has", M.playerOptions(FACTS), ["", "2", "4"])
check("filtered by players", titles(M.applyFilters(FACTS, { players: "4" })), ["Gauntlet"])
check("and said as words", [M.playersLabel(""), M.playersLabel("1"), M.playersLabel("4")], ["Any players", "1 player", "4 players"])
check("show the ones that won't start", titles(M.applyFilters(FACTS, { show: "broken" })), ["Metal Slug"])
check("a genre filter counts as a filter", M.filtersActive({ show: "all", genre: "Maze" }), true)
check("the facts line tells what kind of game",
      M.gameFacts(FACTS[1], 0), "Midway  ·  1981  ·  Maze / Action  ·  2 players  ·  vertical screen  ·  mspacman.zip")
check("the footer gives the whole reason", M.problemNote(FACTS[2]), "Won't start: 13 files are missing")
check("and nothing for one that starts", M.problemNote(FACTS[0]), "")
check("a tile that won't start says so first", M.tileNote(FACTS[2], 0, "last played"), "won't start  ·  13 files are missing")

const ARTMAP = { bublbobl: "/a/bublbobl.png", mspacman: "/a/mspacman.png", gauntlet: "/a/gauntlet.png", mslug: "" }
const ORDER = M.attractOrder(FACTS, ARTMAP, 42)
check("attract mode shows only games with a title screen", titles(ORDER).sort(), ["Bubble Bobble", "Gauntlet", "Ms. Pac-Man"])
check("in an order the seed decides", titles(M.attractOrder(FACTS, ARTMAP, 42)), titles(ORDER))
check("attract mode's wait, in seconds", [M.attractSeconds("60"), M.attractSeconds("off"), M.attractSeconds("")], [60, 0, 0])

// -------------------------------------------------------------- one game

const GAME = M.parseGame([
  "GAME\tbublbobl\tpresent",
  "GAME_FILE\t/c/arcade-games/bublbobl.cfg",
  "TITLE\tBubble Bobble\tdefault",
  "ART\tcustom\tgame",
  "SHADER\tcrt/crt-geom.slangp\tgame",
  "SMOOTH\t\tdefault",
  "ASPECT\tcore\tgame",
  "OPTIONS_SHADER\tnone\tcrt/crt-royale.slangp\tcrt/crt-geom.slangp",
  "BIND\tb1\tspace\tgame",
  "BIND\tb2\tz\tshared",
].join("\n"))
check("the game is read", [GAME.rom, GAME.present], ["bublbobl", true])
const grows = M.gameRows(GAME)
const grow = (k) => grows.find((r) => r.key === k)
check("the name row is typed", [grow("TITLE").kind, grow("TITLE").value], ["text", "Bubble Bobble"])
check("the database's name is not the game's own", M.isOverridden(grow("TITLE")), false)
check("a picture of your own shows as such", M.displayValue(grow("ART")), "your own picture")
check("and lights its own row", [grow("ART_IMAGE").value, M.isOverridden(grow("ART_IMAGE"))], ["custom", true])
check("shaders are offered by name", grow("SHADER").options, ["", "none", "crt/crt-royale.slangp", "crt/crt-geom.slangp"])
check("and shown by name", M.displayValue(grow("SHADER")), "crt-geom")
check("nothing set is RetroArch's", [M.displayValue(grow("SMOOTH")), M.describeSource(grow("SMOOTH"))],
      ["as RetroArch", "as RetroArch has it"])
check("a set one says it is this game's", M.describeSource(grow("ASPECT")), "set for this game only")
check("the shape reads as words", M.displayValue(grow("ASPECT")), "the game's own")
check("a control of its own", [grow("b1").value, grow("b1").source, M.isOverridden(grow("b1"))], ["space", "game", true])
check("a shared one", [grow("b2").value, M.describeSource(grow("b2"))], ["z", "the arcade's control, shared by every game"])
check("controls say they are this game's", grow("b1").group, "Controls for this game")
check("a pending change shows before it is written",
      M.displayValue(M.withPending(grows, { SMOOTH: "smooth" }).find((r) => r.key === "SMOOTH")), "smoothed")
check("a name change re-reads the wall", M.gameWriteEffects(["TITLE"]), { library: true, artwork: false })
check("an artwork change re-dresses the tile", M.gameWriteEffects(["ART"]), { library: false, artwork: true })

// ------------------------------------------------------------ adding games

const one = M.addSummary("added\tpang.zip\tPang\n")
check("one game added says which", one.title, "Added Pang")
check("and where to go", one.added, ["pang"])
check("with nothing wrong", [one.ok, one.detail], [true, ""])
const mixed = M.addSummary([
  "added\tpang.zip\tPang", "added\tgalaga.zip\tGalaga",
  "rejected\tmslug.zip\t13 files are missing from the romset",
  "skipped\tnotes.txt\tnot a romset (zip, 7z, chd)",
].join("\n"))
check("several are counted", mixed.title, "Added 2 games  ·  2 not added")
check("and the first reason is given, with how many more", mixed.detail,
      "mslug.zip: 13 files are missing from the romset  (+1 more)")
check("progress on a long drop", M.addProgress("checking\tpang.zip\t3\t12"), "Checking pang.zip  (3 of 12)…")
check("a single file needs no count", M.addProgress("checking\tpang.zip\t1\t1"), "Checking pang.zip…")
check("verdicts are not progress", M.addProgress("added\tpang.zip\tPang"), "")
check("progress lines are not verdicts", M.addSummary("checking\tpang.zip\t1\t1\nadded\tpang.zip\tPang").title, "Added Pang")
check("a lone rejection says so plainly", M.addSummary("rejected\tx.zip\tbroken").title, "Not added")
check("a file already there", M.addSummary("exists\tbublbobl.zip\tBubble Bobble").title,
      "Bubble Bobble is already in your collection")
check("a BIOS", M.addSummary("bios\tneogeo.zip\tNeo Geo").title, "BIOS neogeo.zip added")
check("dropped files become paths", M.droppedPaths(["file:///home/k/Down%20loads/pang.zip", "https://x/y.zip"]),
      ["/home/k/Down loads/pang.zip"])

// ----------------------------------------------------------------- versions

const SETS = M.parseList([
  "Pang\t/r/pang.zip\t\t\tPang (World)",
  "Snow Bros.: Nick & Tom\t/r/snowbros.zip\t\t\tSnow Bros. - Nick & Tom (set 1)",
  "Snow Bros. - Nick & Tom (Japan)\t/r/snowbroj.zip\t500\t\tSnow Bros. - Nick & Tom (Japan)",
  "Snow Bros. - Nick & Tom (set 2)\t/r/snowbroa.zip\t\t\tSnow Bros. - Nick & Tom (set 2)",
  "Street Fighter III: New Generation (Japan 970204)\t/r/sfiiij.zip\t\t\tStreet Fighter III: New Generation (Japan 970204)",
  "Street Fighter III: New Generation (USA 970204)\t/r/sfiiiu.zip\t\t\tStreet Fighter III: New Generation (USA 970204)",
  "Super Pang\t/r/spang.zip\t\t\tSuper Pang (World 900914)",
  "mystery\t/r/mystery.zip\t\t\t",
  "mystery2\t/r/mystery2.zip\t\t\t",
].join("\n"))

check("the database title is read", SETS[0].dbTitle, "Pang (World)")
check("brackets come off to make the game",
      M.versionKey(SETS[4]), "title:street fighter iii new generation")
check("the databases' spellings of one title agree",
      M.versionKey({ rom: "snowbroa", dbTitle: "Snow Bros. - Nick _ Tom (set 2)" }),
      M.versionKey({ rom: "snowbros", dbTitle: "Snow Bros. - Nick & Tom (set 1)" }))
check("regional versions are the same game", M.versionKey(SETS[4]), M.versionKey(SETS[5]))
check("a title of your own does not split a game from its versions",
      M.versionKey(SETS[1]), M.versionKey(SETS[3]))
check("different games stay apart", M.versionKey(SETS[0]) !== M.versionKey(SETS[6]), true)
check("games the database does not know never group", M.versionKey(SETS[7]) !== M.versionKey(SETS[8]), true)

const grouped = M.groupGames(SETS, {})
const byRom = Object.fromEntries(grouped.map((t) => [t.rom, t]))
check("one tile per game", grouped.map((t) => t.rom),
      ["pang", "snowbroj", "sfiiij", "spang", "mystery", "mystery2"])
check("the version played last stands for it", byRom.snowbroj.versionIndex, 1)
check("with its siblings, the main version first",
      byRom.snowbroj.versions.map((v) => v.rom), ["snowbros", "snowbroj", "snowbroa"])
check("never played, the shortest name is the main version",
      M.mainVersion(byRom.sfiiij.versions).rom, "sfiiij")
check("a single version is just a game", M.versionCount(byRom.pang), 1)

const stepped = M.stepVersion({}, byRom.snowbroj, 1)
check("Tab picks the next version", M.groupGames(SETS, stepped)[1].rom, "snowbroa")
check("and wraps round", M.groupGames(SETS, M.stepVersion({}, byRom.snowbroj, 2))[1].rom, "snowbros")
check("the game running wins over the one played last",
      M.groupGames(SETS.map((g) => g.rom === "snowbroa" ? Object.assign({}, g, { playing: true }) : g), {})[1].rom,
      "snowbroa")

check("the tile says which version it is", M.tileNote(byRom.snowbroj, 500 + 60),
      "2 of 3 versions  ·  1 minute ago")
check("and the footer how to reach the rest", M.versionNote(byRom.snowbroj), "Tab for the other 2 versions")
check("a game with one version says nothing about it", M.versionNote(byRom.pang), "")

// -------------------------------------------------------------- the stick

const PAD = M.parseController([
  "PAD\tNintendo Co., Ltd. Pro Controller\t057e:2009\t/dev/input/event28\that",
  "PROFILE\t/usr/share/libretro/autoconfig/udev/Nintendo Switch Pro Controller.cfg\tNintendo Switch Pro Controller",
  "BIND\tb\t0\tB", "BIND\ta\t1\tA", "BIND\tx\t2\tX", "BIND\ty\t3\tY",
  "BIND\tselect\t9\tMinus", "BIND\tstart\t10\tPlus",
  "BIND\tup\th0up\tD-Pad Up", "BIND\tl\t5\tL", "BIND\tr\t6\tR", "BIND\tl2\t7\tZL",
  "BIND\tmenu_toggle\t11\tHome",
].join("\n"))

check("the controller is read", PAD.pad.name, "Nintendo Co., Ltd. Pro Controller")
check("with its profile", PAD.profile.name, "Nintendo Switch Pro Controller")
check("Button 1 is the stick's B", M.controlPadLabel(PAD, "b1"), "B")
check("Button 3 its Y", M.controlPadLabel(PAD, "b3"), "Y")
check("Button 6 its L", M.controlPadLabel(PAD, "b6"), "L")
check("coin is Minus", M.controlPadLabel(PAD, "coin1"), "Minus")
check("directions are the lever", M.controlPadLabel(PAD, "up1"), "lever")
check("player 2 is not on player 1's stick", M.controlPadLabel(PAD, "coin2"), "")
check("Home is the stick's way out of a game", M.controlPadLabel(PAD, "exit"), "Home")
check("and not RetroArch's menu any more", M.controlPadLabel(PAD, "menu"), "")

check("never launched with it, it is ready but not confirmed", M.controllerStatus(PAD).state, "ready")
const SEEN = Object.assign({}, PAD, { seen: [{ port: 1, name: "Nintendo Co., Ltd. Pro Controller" }] })
check("RetroArch's word at the last launch confirms it", M.controllerStatus(SEEN).state, "ok")
check("no controller is a problem", M.controllerStatus(M.parseController("")).state, "problem")
check("nor is one RetroArch has no profile for",
      M.controllerStatus(M.parseController("PAD\tOdd Pad\t1234:5678\t/dev/input/event9\that")).text,
      "RetroArch has no profile for “Odd Pad”, so games will not know its buttons.")
check("a lever reporting as an analog stick is caught",
      M.controllerStatus(M.parseController("PAD\tX\t1:2\t/e\tnone\nPROFILE\t/p\tX")).state, "problem")

let pressed = M.padEvent({ held: {}, last: null, presses: 0 }, PAD, "button\t0\t1")
check("pressing B lights Button 1", M.controlHeld(pressed, "b1"), true)
check("and says so", [pressed.last.label, pressed.last.meaning], ["B", "Button 1"])
check("with what fighters make of it", pressed.last.note, "“Light Kick” in 3-punch, 3-kick fighters.")
pressed = M.padEvent(pressed, PAD, "button\t0\t0")
check("letting go puts it out", M.controlHeld(pressed, "b1"), false)
check("but remembers what it was", pressed.last.meaning, "Button 1")
check("the lever is a direction",
      M.padEvent(pressed, PAD, "hat\tup\t1").last.meaning, "Up")
check("coin is coin", M.padEvent(pressed, PAD, "button\t9\t1").last.meaning, "Insert coin")
check("ZL does nothing in arcade games",
      M.padEvent(pressed, PAD, "button\t7\t1").last.meaning, "not used by arcade games")
check("an analog stick is flagged",
      M.padEvent(pressed, PAD, "axis\t-0\t1").last.meaning, "not seen by arcade games")
check("a button no profile binds says so",
      M.padEvent(pressed, PAD, "button\t4\t1").last.meaning, "not bound in RetroArch")
check("Home takes you back to the arcade", M.padEvent(pressed, PAD, "button\t11\t1").last.meaning, "Back to the arcade")
check("a garbled line changes nothing", M.padEvent(pressed, PAD, "nonsense"), null)

check("a press is read as the RetroPad button it is", M.padPress(PAD, "button\t0\t1"),
      { kind: "button", which: "0", down: true, retropad: "b" })
check("B plays", M.stickAction("b", "wall"), "play")
check("so does Start", M.stickAction("start", "wall"), "play")
check("the lever moves", M.stickAction("left", "wall"), "left")
check("Y and X step through versions", [M.stickAction("y", "wall"), M.stickAction("x", "wall")],
      ["version-prev", "version-next"])
check("L and R page", [M.stickAction("l", "wall"), M.stickAction("r", "wall")], ["page-up", "page-down"])
check("A goes back", M.stickAction("a", "wall"), "back")
check("Home closes", M.stickAction("menu_toggle", "wall"), "close")
check("coin opens the settings", M.stickAction("select", "wall"), "settings")
check("in the settings B changes a row", M.stickAction("b", "settings"), "activate")
check("and A leaves them", M.stickAction("a", "settings"), "back")
check("with a problem showing, B re-checks", M.stickAction("b", "problem"), "recheck")
check("buttons with no job do nothing", M.stickAction("select", "problem") && M.stickAction("y", "problem"), "")
check("a held lever repeats", M.stickRepeats("down"), true)
check("a held B does not", M.stickRepeats("play"), false)

const padRows = M.controllerRows(PAD)
check("the editor names the profile the stick is known by", padRows[0].value, "Nintendo Switch Pro Controller")
check("and says whether it will work", M.describeSource(padRows[0]),
      "RetroArch will use its Nintendo Switch Pro Controller profile. Start a game once to confirm.")
check("a problem is shown as one", M.describeState(M.controllerRows(M.parseController(""))[0]),
      "No controller connected. Plug it in and press F5.")
check("the test comes next", padRows[1].kind, "padtest")

// ----------------------------------------------------------------- matching

check("empty query keeps everything", titles(M.filterGames(games, "")).length, 6)
check("whitespace is not a query", titles(M.filterGames(games, "   ")).length, 6)
check("case does not matter", titles(M.filterGames(games, "BUBBLE")), ["Bubble Bobble"])
check("the short name finds it too", titles(M.filterGames(games, "bublbobl")), ["Bubble Bobble"])
check("a prefix outranks a substring",
      titles(M.filterGames(games, "pang")), ["Pang", "Super Pang"])
check("a word inside the title still matches",
      titles(M.filterGames(games, "monster")), ["Wonder Boy in Monster Land"])
check("ties keep the incoming order",
      titles(M.filterGames(games, "snow")),
      ["Snow Bros. 2: With New Elves", "Snow Bros.: Nick & Tom"])
check("no match is an empty list", M.filterGames(games, "zzz"), [])

// ---------------------------------------------------------------- selection

check("clamp holds the top", M.clampIndex(-3, 5), 0)
check("clamp holds the bottom", M.clampIndex(9, 5), 4)
check("clamp of an empty list", M.clampIndex(3, 0), 0)
check("down wraps to the first", M.wrapIndex(4, 1, 5), 0)
check("up wraps to the last", M.wrapIndex(0, -1, 5), 4)
check("a page jump stays inside", M.wrapIndex(0, 10, 6), 4)
check("moving in an empty list", M.wrapIndex(0, 1, 0), 0)

// ---------------------------------------------------------------- formatting

check("home is shortened", M.shortenPath("/home/kimm/Games/roms/pang.zip", HOME), "~/Games/roms/pang.zip")
check("other paths are left alone", M.shortenPath("/opt/roms/pang.zip", HOME), "/opt/roms/pang.zip")
check("the whole library", M.describeCount(28, 28), "28 games")
check("one game is singular", M.describeCount(1, 1), "1 game")
check("a filtered list says both", M.describeCount(3, 28), "3 of 28")
check("nothing to show", M.describeCount(0, 0), "no games")

// --------------------------------------------------------------------- grid

check("columns fit the width", M.columnsFor(1000, 240, 16), 4)
check("a narrow panel still has two", M.columnsFor(300, 240, 16), 2)
check("a very wide one is capped", M.columnsFor(4000, 240, 16), 8)
check("the cap is settable", M.columnsFor(4000, 240, 16, 6), 6)
check("tiles stay near their target width", M.columnsFor(1840, 300, 14, 6), 6)
check("right flows into the next row", M.gridTarget(3, 1, 28), 4)
check("down is a row", M.gridTarget(0, 4, 28), 4)
check("the end clamps", M.gridTarget(26, 4, 28), 27)
check("the start clamps", M.gridTarget(1, -4, 28), 0)
check("rows of an index", [M.rowOf(0, 4), M.rowOf(7, 4)], [0, 1])

// ------------------------------------------------------------------ artwork

check("a path is recorded", M.withArt({}, "pang\t/art/pang.png"), { pang: "/art/pang.png" })
check("a miss is recorded as empty", M.withArt({}, "pang\t"), { pang: "" })
check("an unchanged line changes nothing", M.withArt({ pang: "" }, "pang\t"), null)
check("a malformed line is ignored", M.withArt({}, "pang"), null)
check("the map is not mutated in place", (() => {
  const before = { a: "1" }
  M.withArt(before, "b\t2")
  return before
})(), { a: "1" })

const artGames = M.parseList(LIST)
check("art for a game", M.artFor({ pang: "/art/pang.png" }, artGames[1]), "/art/pang.png")
check("no art is an empty string", M.artFor({ pang: "" }, artGames[1]), "")
check("unknown is still pending", M.artPending({}, artGames[1]), true)
check("a recorded miss is not pending", M.artPending({ pang: "" }, artGames[1]), false)
check("only unknown roms are wanted",
      M.artWanted({ bublbobl: "/a.png", pang: "" }, artGames, 10),
      ["snowbro2", "snowbros", "spang", "wbml"])
check("wanting is capped", M.artWanted({}, artGames, 2).length, 2)

check("initials of a plain title", M.initials("Bubble Bobble"), "BB")
check("digits count", M.initials("1942"), "1")
check("punctuation is skipped", M.initials("Snow Bros.: Nick & Tom"), "SBN")
check("nothing at all", M.initials(""), "?")

// ----------------------------------------------------------------- settings

const SETTINGS = [
  "CONFIG_FILE\t/home/kimm/.config/omarchy/arcade.conf\tpresent",
  "ROM_DIR\t/home/kimm/Games/neogeo\tfile\tok",
  "ROM_EXTS\tzip 7z chd\tdefault\tok",
  "CORE_PATH\t/usr/lib/libretro/fbneo_libretro.so\tauto\tok",
  "RETROARCH_CONFIG\t\tdefault\tok",
  "ARTWORK\toff\tfile\tok",
  "ART_KINDS\tsnaps\tfile\tok",
  "TILE_SIZE\t240\tfile\tok",
  "MAX_COLUMNS\t6\tdefault\tok",
  "MENU_CMD\t\tauto\tok",
  "OPTIONS_CORE_PATH\t/usr/lib/libretro/fbneo_libretro.so\t/usr/lib/libretro/mame_libretro.so",
].join("\n")

const parsed = M.parseSettings(SETTINGS)
check("the config path is picked out", parsed.configFile, "/home/kimm/.config/omarchy/arcade.conf")
check("and whether it exists", parsed.configPresent, true)
check("a value and its source", parsed.values.ROM_DIR,
      { value: "/home/kimm/Games/neogeo", source: "file", state: "ok" })
check("an empty value is still a value", parsed.values.RETROARCH_CONFIG,
      { value: "", source: "default", state: "ok" })
check("a blank line is ignored", M.parseSettings("\n\nROM_DIR\t/x\tfile").values.ROM_DIR,
      { value: "/x", source: "file", state: "ok" })
check("an older report with no state column still reads",
      M.parseSettings("ROM_DIR\t/x\tfile").values.ROM_DIR.state, "ok")
check("the offered options are picked out", parsed.options.CORE_PATH.length, 2)
check("an options line is not a setting", parsed.values.OPTIONS_CORE_PATH, undefined)

const rows = M.settingsRows(parsed)
const byKey = Object.fromEntries(rows.map((r) => [r.key, r]))
check("every schema row is present", rows.length, M.settingsSchema().length)
check("rows carry the reported value", byKey.ROM_DIR.value, "/home/kimm/Games/neogeo")
check("a key the launcher did not report is empty", byKey.ART_DIR.value, "")
check("a hand-edited choice keeps its value as an option",
      byKey.ART_KINDS.options.includes("snaps"), true)
check("only a file-set row counts as overridden",
      [M.isOverridden(byKey.ROM_DIR), M.isOverridden(byKey.CORE_PATH)], [true, false])
check("an autodetected core says so", M.describeSource(byKey.CORE_PATH), "autodetected")
check("an empty autodetect says nothing was found", M.describeSource(byKey.MENU_CMD), "nothing found")
check("an empty core reads as autodetect",
      M.displayValue({ key: "CORE_PATH", value: "", kind: "path" }, HOME), "autodetect")
check("a path is shown under the home tilde", M.displayValue(byKey.ROM_DIR, HOME), "~/Games/neogeo")

check("a number out of range is refused", M.validateSetting(byKey.MAX_COLUMNS, "99"), "at most 12")
check("a number below range is refused", M.validateSetting(byKey.TILE_SIZE, "10"), "at least 140")
check("a non-number is refused", M.validateSetting(byKey.TILE_SIZE, "big"), "a whole number")
check("a number in range is fine", M.validateSetting(byKey.TILE_SIZE, "320"), "")
check("an empty ROM directory is refused", M.validateSetting(byKey.ROM_DIR, "  "), "a directory is required")
check("an empty core is fine", M.validateSetting(byKey.CORE_PATH, ""), "")
check("a tab is refused", M.validateSetting(byKey.ROM_DIR, "/a\tb"), "no tabs or newlines")
check("extensions must look like extensions", M.validateSetting(byKey.ROM_EXTS, "zip;rm -rf"),
      "extensions, space separated")

check("extensions are stored bare", M.normalizeSetting(byKey.ROM_EXTS, " *.ZIP  .7z "), "zip 7z")
check("a number is stored without padding", M.normalizeSetting(byKey.TILE_SIZE, " 320 "), "320")
check("a path keeps its shape", M.normalizeSetting(byKey.ROM_DIR, " $HOME/Games/roms "), "$HOME/Games/roms")

check("setting an argument", M.settingArg("ROM_DIR", "~/roms"), "ROM_DIR=~/roms")
check("resetting is an empty argument", M.settingArg("TILE_SIZE", ""), "TILE_SIZE=")

check("a choice steps forward", M.cycleOption(["on", "off"], "on", 1), "off")
check("and wraps backwards", M.cycleOption(["on", "off"], "on", -1), "off")
check("an unknown value starts at the first", M.cycleOption(["on", "off"], "maybe", 1), "off")
check("a number steps by its step", M.stepNumber(byKey.TILE_SIZE, "240", 1), "260")
check("and stops at the ends", M.stepNumber(byKey.MAX_COLUMNS, "12", 1), "12")
check("an empty number starts at the minimum", M.stepNumber(byKey.TILE_SIZE, "", 1), "160")

check("the panel reads its own sizes", M.settingNumber(parsed, "TILE_SIZE", 300), 240)
check("a missing one falls back", M.settingNumber(parsed, "ART_DIR", 300), 300)
check("the ROM directory invalidates the library", M.affectsLibrary("ROM_DIR"), true)
check("the tile size does not", M.affectsLibrary("TILE_SIZE"), false)
check("artwork policy invalidates the art map", M.affectsArtwork("ART_KINDS"), true)

check("an offered core row becomes a list", byKey.CORE_PATH.kind, "choice")
check("with autodetect leading it", byKey.CORE_PATH.options[0], "")
check("and the installed cores after", byKey.CORE_PATH.options.length, 3)
check("a row with nothing offered stays typed", byKey.MENU_CMD.kind, "text")
check("autodetect is a legal choice there", M.validateSetting(byKey.CORE_PATH, ""), "")
check("but not for a plain choice", M.validateSetting(byKey.ARTWORK, ""), "pick one")
check("cycling off autodetect picks the first core",
      M.cycleOption(byKey.CORE_PATH.options, "", 1), "/usr/lib/libretro/fbneo_libretro.so")

const MISSING = M.settingsRows(M.parseSettings(
  "ROM_DIR\t/nowhere\tfile\tmissing\nCORE_PATH\t/nowhere/core.so\tfile\tmissing"))
check("a directory that is not there is called out",
      M.describeState(MISSING.find((r) => r.key === "ROM_DIR")), "no such directory")
check("and a file that is not there", M.describeState(MISSING.find((r) => r.key === "CORE_PATH")),
      "no such file")
check("a row that is fine says nothing", M.describeState(byKey.ROM_DIR), "")

check("a pending value shows before it is written",
      M.withPending(rows, { TILE_SIZE: "280" }).find((r) => r.key === "TILE_SIZE").value, "280")
check("and reads as the user's own", M.withPending(rows, { TILE_SIZE: "280" })
      .find((r) => r.key === "TILE_SIZE").source, "file")
check("a pending reset reads as a default again",
      M.withPending(rows, { ROM_DIR: "" }).find((r) => r.key === "ROM_DIR").source, "default")
check("rows with nothing pending are untouched",
      M.withPending(rows, { TILE_SIZE: "280" }).find((r) => r.key === "ROM_EXTS").value, "zip 7z chd")
check("everything waiting goes in one write",
      M.pendingArgs({ TILE_SIZE: "280", MAX_COLUMNS: "4" }).sort(),
      ["MAX_COLUMNS=4", "TILE_SIZE=280"])

// ----------------------------------------------------------------- controls

const CONTROLS = [
  "CONTROLS_FILE\t/home/kimm/.config/omarchy/arcade-retroarch.cfg\tpresent",
  "PRESET\tmame\tok",
  "coin1\tnum5\tfile",
  "start1\tnum1\tfile",
  "b1\tctrl\tfile",
  "coin2\tnul\tretroarch",
  "exit\tescape\tretroarch",
].join("\n")

const controls = M.parseControls(CONTROLS)
check("the profile is picked out", controls.present, true)
check("and the layout it matches", controls.preset, "mame")
check("a bind and where it came from", controls.values.coin1, { key: "num5", source: "file" })
check("no profile yet means no layout was chosen",
      M.controlRows(M.parseControls("CONTROLS_FILE\t/x\tabsent\nPRESET\tretroarch\tok"))[0].source,
      "default")

const cRows = M.controlRows(controls)
const cByKey = Object.fromEntries(cRows.map((r) => [r.key, r]))
check("the layout leads the controls", cRows[0].key, "CONTROLS_PRESET")
check("every control has a row", cRows.length, M.controlsSchema().length + 1)
check("a control row is a bind", cByKey.CONTROL_coin1.kind, "bind")
check("carrying its key", cByKey.CONTROL_coin1.value, "num5")
check("a bind from RetroArch's own config says so",
      M.describeSource(cByKey.CONTROL_exit), "from your RetroArch config")
check("one set for the arcade says that", M.describeSource(cByKey.CONTROL_coin1), "set for the arcade")
check("one bound nowhere is RetroArch's own default",
      M.describeSource(M.controlRows(M.parseControls("CONTROLS_FILE\t/x\tabsent\nstart1\tenter\tdefault"))
        .find((r) => r.key === "CONTROL_start1")), "RetroArch's default")

check("the coin key reads as the 5 you press", M.controlDisplay(cByKey.CONTROL_coin1), "5")
check("a modifier says which side", M.controlDisplay(cByKey.CONTROL_b1), "Left Ctrl")
check("an unbound control says so", M.controlDisplay(cByKey.CONTROL_coin2), "unbound")
check("the layout row shows the layout's name", M.controlDisplay(cRows[0]), "MAME standard")
check("a hand-edited profile is a layout of its own",
      M.layoutLabel("custom"), "custom")

// Qt key codes in, retroarch.cfg key names out.
const KEYPAD = 0x20000000
check("a letter is itself", M.retroarchKey(0x5a, 0, "z"), "z")
check("shift does not change the bind", M.retroarchKey(0x5a, 0x02000000, "Z"), "z")
check("a digit is a num", M.retroarchKey(0x35, 0, "5"), "num5")
check("a keypad digit is a keypad", M.retroarchKey(0x35, KEYPAD, "5"), "keypad5")
check("shift does not change a digit either", M.retroarchKey(0x35, 0x02000000, "%"), "num5")
check("space", M.retroarchKey(0x20, 0, " "), "space")
check("left ctrl", M.retroarchKey(0x01000021, 0x04000000, ""), "ctrl")
check("return is enter", M.retroarchKey(0x01000004, 0, "\r"), "enter")
check("the keypad's is not", M.retroarchKey(0x01000005, KEYPAD, "\r"), "kp_enter")
check("an arrow", M.retroarchKey(0x01000012, 0, ""), "left")
check("f-keys count up", [M.retroarchKey(0x01000030, 0, ""), M.retroarchKey(0x0100003b, 0, "")],
      ["f1", "f12"])
check("punctuation has a name", M.retroarchKey(0x2d, 0, "-"), "minus")
check("a key with no name binds nothing", M.retroarchKey(0x01000022, 0, ""), "")

// ------------------------------------------------------------------ report

if (failures.length) {
  for (const f of failures) console.error("  FAIL  " + f)
  console.error(`\n  ${failures.length} of ${checks} checks failed`)
  process.exit(1)
}
console.log(`  ok  ${checks} checks`)
