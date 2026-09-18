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
