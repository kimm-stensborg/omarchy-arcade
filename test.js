#!/usr/bin/env node
// Model.js unit tests.
//
//     node test.js        # prints every failure, exits 1 if any
//
// Model.js owns the parsing and the match ranking -- the parts that decide
// which ROM Enter launches. Getting that wrong starts the wrong game, so it is
// checked here rather than by playing.
//
// Model.js is loaded by evaluating it, minus the QML `.pragma library` line
// that node cannot parse, and re-exporting whatever it declares.

const fs = require("fs")
const path = require("path")

function loadModel() {
  const src = fs.readFileSync(path.join(__dirname, "Model.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")
  const names = []
  for (const m of src.matchAll(/^(?:function|var)\s+([A-Za-z_$][\w$]*)/gm)) names.push(m[1])
  return new Function(src + "\nreturn {" + names.join(", ") + "}")()
}

const M = loadModel()
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
check("path is the rest", games[0].path, "/home/kimm/Games/roms/bublbobl.zip")
check("rom name comes off the path", games[0].rom, "bublbobl")
check("a title may contain a colon", games[2].title, "Snow Bros. 2: With New Elves")
check("nothing parses to nothing", M.parseList(""), [])
check("trailing newline adds no row", M.parseList("A\t/a.zip\n").length, 1)
// A row with no tab cannot say which file it would launch.
check("a row without a tab is dropped", M.parseList("just a title").length, 0)
check("an empty path is dropped", M.parseList("Title\t").length, 0)

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

// ------------------------------------------------------------------ report

if (failures.length) {
  for (const f of failures) console.error("  FAIL  " + f)
  console.error(`\n  ${failures.length} of ${checks} checks failed`)
  process.exit(1)
}
console.log(`  ok  ${checks} checks`)
