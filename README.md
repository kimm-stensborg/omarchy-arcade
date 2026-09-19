# Arcade

A summoned overlay that lists your arcade ROMs by their real names and boots
the one you pick straight into RetroArch. No RetroArch menu, no `bublbobl.zip`,
no extra menu program to install.

- **Plugin ID:** `io.github.kimm-stensborg.arcade`
- **Kind:** `overlay`
- **License:** MIT
- **Requires:** Omarchy 4 (Quattro) with `omarchy-shell`

![Arcade](preview.png)

Every tile is the game's own title screen, fetched once from libretro's
thumbnail server and cached locally. Type to filter, arrow around, Enter plays.

## Dependencies

| Package | Used for |
|---------|----------|
| `retroarch` | running the games |
| `libretro-fbneo-git` *or* `libretro-mame` | the arcade core |
| `python` | `bin/arcade-rdb-dump`, which reads the libretro databases |
| `zenity` | the file chooser for adding games (optional; drag and drop works without it) |
| `libretro-database-git` | the title database (ships with RetroArch on Omarchy) |

Nothing is fetched at runtime. `wofi`, `rofi` or `fuzzel` are optional: the
launcher script can also show its own menu outside the shell, but the overlay
never needs one.

## Install

```bash
omarchy plugin add https://github.com/kimm-stensborg/omarchy-arcade.git
~/.config/omarchy/plugins/io.github.kimm-stensborg.arcade/install.sh
```

Plugins land disabled so the code can be read before it runs — they execute
unsandboxed inside `omarchy-shell`. `install.sh` is the second half of that: it
proposes a shortcut, binds the one you accept, and then enables the plugin.

It proposes `SUPER + A` — *arcade*, free on a stock Omarchy — or the first free
fallback if Hyprland already has it. Edit the proposal to anything you prefer,
press Enter, and the block lands in `~/.config/hypr/bindings.lua`:

```lua
-- Arcade overlay (io.github.kimm-stensborg.arcade)
o.bind("SUPER + A", "Arcade", "omarchy-shell shell toggle io.github.kimm-stensborg.arcade '{}'")
hl.config({ general = { allow_tearing = true } })
o.window("com.libretro.RetroArch", { immediate = true, no_anim = true })
```

`toggle` rather than `summon`, so the same key closes it. Choosing a
combination that is already bound says what it is bound to and asks before
taking it over. Re-running the script replaces its own block rather than
stacking a second one, so it is also how you change the shortcut later.

The two window rules are what makes RetroArch behave like a cabinet:
`immediate` presents frames the moment they are rendered instead of waiting for
the compositor's vsync — lower input latency, at the cost of visible tearing —
and needs `allow_tearing`, which Omarchy defaults to false. Omarchy's own
`retroarch.lua` already opens it fullscreen and inhibits idle. Delete those two
lines if you would rather have neither.

```bash
install.sh --key "SUPER + F12"   # skip the prompt
install.sh --no-bind             # just enable the plugin
install.sh --no-link             # skip the ~/.local/bin symlinks
./uninstall.sh [--purge]         # remove the block and the symlinks
omarchy plugin remove io.github.kimm-stensborg.arcade
```

`install.sh` also seeds `~/.config/omarchy/arcade.conf` and
`arcade-titles.tsv` (only when they do not exist), builds the title cache, and
links `arcade-launcher`, `arcade-rdb-dump` and `arcade-artwork` into
`~/.local/bin` for use from a terminal.

## Keys

| Key | Does |
|-----|------|
| type | filter by title or ROM name |
| `←` `↑` `↓` `→`, `Ctrl+P` `Ctrl+N` | move the selection |
| `PgUp` `PgDn`, `Home` `End` | jump |
| `Enter` | launch the selected game, or return to it if it is running |
| `Tab` `Shift+Tab` | another version of the selected game |
| `Alt+F` | make the selected game a favourite, or not |
| `Alt+O` | the next sort order: last played, favourites, most played, name, year (`Shift` for the previous) |
| `Alt+V` `Alt+D` `Alt+M` | filter: which games, decade, maker (`Shift` for the previous) |
| `Alt+0` | clear the filters |
| `Alt+E` | this game's own settings: name, artwork, picture, controls (again to close them) |
| `Alt+A` | add games: pick romsets in a file chooser (or `+` in the header) |
| `F5` | re-read the ROM directory |
| `Alt+S` | open the settings, controls included (again to close them) |
| `Esc` | close |

## The wall

The wall is the whole library in one grid, in the order the **Sort** chip
under the search field says:

| Sort | Order |
|------|-------|
| Last played | newest first, then the games never played, by name. The default: opening the panel and pressing `Enter` puts you back in the last game |
| Favourites | your favourites first, then the rest, each by name |
| Most played | the most plays first; a tie goes to the one played last |
| Name | alphabetical |
| Year | oldest first; a game the database dates only to a decade ("198?") comes after that decade's dated ones, and a game with no year comes last |

`Alt+O` steps through them (`Shift` goes back), and so does a click on the
chip (a right click goes back). The order is written to `arcade.conf` as
`SORT_BY`, so the wall opens the same way next time. The line under each tile
fits the order: the plays when sorted by plays, the year when sorted by year,
otherwise when you last played it.

The chips beside it filter the wall, and are lit while they do:

| Chip | Key | Shows |
|------|-----|-------|
| All games / Favourites / Played / Never played | `Alt+V` | which games |
| a decade | `Alt+D` | only the games from that decade, e.g. 1980s |
| a maker | `Alt+M` | only that maker's games. The makers with the most games come first |
| Clear filters | `Alt+0` | everything again |

The decades and makers on offer are the ones your library actually has, so no
choice ever leaves the wall empty by itself. A search keeps the filters, but
ranks by how well each game matches rather than by the sort. Filters are for
one open of the panel, like the search: it always opens on the whole library.

When you last played a game and how often come from
`~/.local/state/omarchy/arcade-history.tsv`. The first time the panel opens
after an upgrade, that history is built from the launch headers already in
`arcade.log`.

### Favourites

`Alt+F` (or ZL/ZR on the stick) makes the selected game a favourite, and a
heart appears beside its name. The same key takes it off again. Sort by
**Favourites** to have them lead the wall, or show only **Favourites** with
`Alt+V`.

A favourite belongs to the game, not to one version of it: marking Street
Fighter III in its Japanese version marks the tile, whichever version `Tab`
shows. Favourites are kept by ROM name, one per line, in
`~/.config/omarchy/arcade-favourites`, so they survive moving `ROM_DIR` and
are easy to edit by hand. From a terminal:

```bash
arcade-launcher --favourite bublbobl pang
arcade-launcher --unfavourite pang
```

The selected game lifts out of the wall with a glow, and its title screen,
blurred, lights the whole screen behind the panel. The bar along the bottom
names it, with its maker and year from the libretro database, how many versions
there are, when you last played it, and its file. The keys to press are
alongside as keycaps, and switch to the stick's buttons when the stick was
the last thing used.

One game runs at a time. The one running is marked **PLAYING**, and the
footer says what `Enter` will do before you press it: on that game it brings it
back to the front, and on any other game it closes the running one and starts
the new one. RetroArch quits cleanly on the way out, so high scores are saved.
If you opened RetroArch yourself, it is left alone: the launcher brings it to
the front and asks you to close it first.

### Versions

A romset library often holds the same game several times: `sfiii`, `sfiiiu`
and `sfiiij` are Street Fighter III for Europe, the USA and Japan. The wall
shows each game once and says how many versions it has under the tile.
`Tab` steps through them in place, and whichever one is showing is the one
`Enter` starts.

Nothing on the machine records which set is a clone of which, so versions are
grouped by their database title with the bracketed part removed:
"Street Fighter III: New Generation (Japan 970204)" and "(USA 970204)" are the
same game. The version a tile shows is the one you picked with `Tab`, otherwise
the one running, otherwise the one you played last. Failing all three it is
the main version: the shortest ROM name (the parent set, nearly always). When
names are the same length, a set you gave a title of your own wins, then one
the database calls "set 1" or "World". A search lists every version on its
own, so typing `sfiiij` finds exactly that one. `GROUP_VERSIONS="off"` shows
every version on the wall. ROMs the database does not know are never grouped.

### When a game does not start

A romset with files missing does not make RetroArch exit. The core unloads,
and RetroArch sits in its own menu, so from a keybinding it looks like nothing
happened. The launcher therefore reads RetroArch's log (it runs with
`--verbose`) until the game shows a picture. If the core gives up instead,
RetroArch is closed and a notification says why:

> **Metal Slug did not start.** 13 files are missing from the romset
> (201-p1.p1, 201-s1.s1, 201-c1.c1, ...) -- it may be for another version, or
> need its BIOS.

A launch that failed is not counted as a game played. The launcher waits up to
twenty seconds for an answer: a large CHD can take that long to load, and a
guess would close a game that was about to start.

## A game's own settings

`Alt+E`, or the pencil beside the heart on the selected tile, opens the
settings of that one game, in the same editor as the arcade's own:

| Row | Does |
|-----|------|
| Name | the name on the wall and in search. Empty goes back to the database's |
| Artwork | title screen, in-game or box art; changing it fetches that kind |
| Your own picture | a PNG or JPEG of your own for the tile, chosen in a file chooser |
| Shader | none, or a CRT look (crt-royale, crt-geom, crt-lottes, …) from RetroArch's slang shaders |
| Smoothing | sharp pixels or smoothed |
| Shape | the game's own, 4:3, fill the screen, or square pixels |
| Whole-number scaling | every pixel the same size, with a border round the picture |
| Rotation | for a screen mounted on its side |
| Controls for this game | any control changed for this game only; the rest stay the arcade's |

Every row starts out following the arcade or RetroArch, and says so. `Delete`
hands a row back. Only what you change is written, to
`~/.config/omarchy/arcade-games/<rom>.cfg`, a RetroArch config that is loaded
after the arcade's controls when the game starts. So a game's changes win for
that game and nowhere else, and nothing reaches your everyday
`retroarch.cfg`. The name goes to `arcade-titles.tsv`, like any title of your
own.

From a terminal:

```bash
arcade-launcher --game bublbobl                       # what is set, and where from
arcade-launcher --game-set sf2 SHADER=crt/crt-royale.slangp b1=a b4=s
arcade-launcher --game-set sf2 SHADER=                # back to RetroArch's
arcade-launcher --game-image bublbobl ~/Pictures/bb.png
```

## Adding games

Two ways in, and both take as many files as you like at once:

- **`+` in the header, or `Alt+A`, opens a file chooser**: your desktop's
  own, multi-select, filtered to `.zip`, `.7z` and `.chd`, and opening in the
  folder you picked from last time (the download folder the first time). The
  panel hides while it is open, so the chooser has the screen and the
  keyboard, and comes back with the result, or as it was if you cancel.
- **Drop files anywhere on the panel**, from a file manager on another monitor
  for instance, a whole folder included (the romsets in it, not its
  subfolders).

A big batch counts through in the info bar ("Checking pang.zip (3 of 12)…").

Each file is copied into `ROM_DIR` and then **test-loaded**: RetroArch runs the
core for two frames with no window and no sound, and the same log lines that
catch a failed launch decide whether it runs. It happens inside `ROM_DIR`,
because that is where a game's BIOS is looked for. Only what runs stays:

| Verdict | What happens |
|---------|--------------|
| added | a game that runs; it is kept, its artwork fetched, and the wall goes to it |
| BIOS | a BIOS or device set (`neogeo.zip`, `qsound.zip`); kept without a test, since it is not a game |
| already there | the same file is already in `ROM_DIR` |
| not added | it would not run (for example, "13 files are missing from the romset"), so it is taken out again. A different file with the same name already in `ROM_DIR` is never replaced. A file that is not a `.zip`, `.7z` or `.chd` is skipped |

The info bar sums up the drop ("Added Pang", "Added 2 games · 1 not added") and
gives the first reason anything was turned away. The original files are left
where they were. A test load adds nothing to RetroArch's history, play time or
config.

The same from a terminal, one `result<TAB>file<TAB>detail` line per file:

```bash
arcade-launcher --add ~/Downloads/*.zip   # or a folder: ~/Downloads
arcade-launcher --add $(arcade-launcher --pick)   # choose them in a file chooser
```

## With the stick

A game controller works the panel too, and **Home opens it**. Nothing needs
installing for that: the plugin stays loaded in the shell and follows the
controller RetroArch gives player 1, through unplugging and replugging.

| Stick | On the wall | In the settings |
|-------|-------------|-----------------|
| Home | opens the panel; in a game, closes the game and opens it | closes it |
| lever | moves; held, keeps moving | moves between rows; ← → change a choice |
| B, Start | plays the selected game | changes a choice, starts the stick test |
| A | clears the search, then the filters, then closes | back to the wall |
| Y, X | the previous / next version of the game | |
| L, R | a page up / down | |
| ZL, ZR (L2, R2) | makes the selected game a favourite, or not | |
| L3, R3 (stick clicks) | the next sort order / which games are shown | |
| Minus (coin) | opens the settings | back to the wall |

Buttons are RetroPad buttons, as RetroArch's profile names them, so this holds
for any controller RetroArch knows. **Home is the way back:** in a game it
closes the game (cleanly, so high scores are saved) and opens the panel, ready
for the next pick. That means Home no longer opens RetroArch's own menu from
the stick. RetroArch may show it for a split second as the game closes, and
it is still on `F1` on the keyboard. A RetroArch you started some other way is
never closed: Home leaves it and the panel alone.

While the panel is open it takes the stick for itself (an exclusive grab), so
a game running behind it does not also receive every press. The footer switches to the stick's hints whenever the stick was the last
thing used.

## Search

Matching looks at both names, because half of arcade memory is the short one:
`bublbobl` finds Bubble Bobble, `snow` finds all three Snow Bros., and a title
that *starts* with what you typed outranks one that merely contains it — so
`pang` puts Pang above Super Pang.

## Artwork

Tiles are **title screens** — the game's own logo frame — from
[libretro's thumbnail server](https://thumbnails.libretro.com/), which has
artwork for essentially every arcade romset. `bin/arcade-artwork` fetches them:

- One PNG per ROM in `~/.cache/omarchy/arcade-art/`, downloaded once.
- The first open fetches in the background, four at a time, and tiles fill in
  as images land. Nothing blocks; a game with no art yet shows its initials.
- A game the server has nothing for gets a `.miss` marker, so the next open
  does not ask again. `arcade-artwork --refresh <rom>` forgets that. Only a
  404 counts: no network, a timeout or a server error leaves the game to be
  asked about again next time.
- Preference order is title screen → in-game snap → boxart, since many arcade
  titles never had a box. Change it with `ART_KINDS` in `arcade.conf`.
- `ARTWORK="off"` in `arcade.conf` means never touch the network. Whatever is
  already cached keeps showing.
- A fetch that cannot reach the server says so: one line in
  `~/.cache/omarchy/arcade.log` from `install.sh`, and a warning in the shell
  log from the overlay. Blank tiles always have an explanation somewhere.

The whole library of 28 games took under a second here, a few MB on disk.
`install.sh` kicks off the first fetch in the background so the panel is
already dressed the first time it opens.

```bash
arcade-artwork bublbobl gng          # fetch or report specific games
arcade-artwork --offline bublbobl    # only say what is already cached
arcade-artwork --refresh snowbro3    # forget a recorded miss and retry
```

Images are used as RetroArch itself uses them; they belong to their respective
copyright holders.

## How titles work

Three sources, first hit wins:

1. **`~/.config/omarchy/arcade-titles.tsv`** — your overrides, `romname<TAB>Title`.
2. **`~/.cache/omarchy/arcade-titles.cache.tsv`** — `rom<TAB>title<TAB>year<TAB>maker`, generated from the libretro
   databases in `/usr/share/libretro/database/rdb/` (~46k entries across FBNeo
   and the MAME sets). Built on first run, refreshed whenever a database file
   is newer than the cache.
3. **The filename**, unchanged. An unknown ROM shows as `snowbro3`, never as a
   wrong guess.

The cache gives correct-but-noisy titles (`1942 (Revision B)`); the TSV is where
you trim them. `share/arcade-titles.tsv` ships with a common arcade set already
trimmed, and is used until you have overrides of your own.

Adding one:

```bash
printf 'sfiii3\tStreet Fighter III: 3rd Strike\n' >> ~/.config/omarchy/arcade-titles.tsv
```

The separator must be a real tab, which is why titles may contain colons and
slashes freely. Two ROMs sharing a title both get their ROM name appended, so
the pick stays unambiguous.

BIOS and device sets — `neogeo.zip`, `pgm.zip`, `qsound.zip` — have to sit
next to the games that need them, but are not games, so they are left out of
the list: any set whose title ends in "BIOS" or "Internal ROM", plus a short
list of well-known ones whose title does not say so. Give one a title of your
own in the TSV to bring it back.

## When something is missing

No core installed, no ROMs, no RetroArch — the panel says so in place of the
library, with the exact fix, and `Enter` re-checks. The same report from a
terminal:

```bash
arcade-launcher --doctor
```

It exits with the code of the first problem (`66` no ROM dir, `67` no ROMs,
`68` no core, `69` no menu program, `70` no RetroArch). A launch refused
because a RetroArch the launcher did not start is already running exits `72`.

## Configuration

`~/.config/omarchy/arcade.conf` is a shell fragment; every key can also be set
in the environment for a single run. See
[`share/arcade.conf.example`](share/arcade.conf.example).

| Variable | Default |
| --- | --- |
| `ROM_DIR` | `~/Games/roms` (searched two levels deep) |
| `ROM_EXTS` | `zip 7z chd` |
| `CORE_PATH` | autodetected: FBNeo, then MAME, in `~/.config/retroarch/cores` then `/usr/lib/libretro` |
| `RETROARCH_CONFIG` | unset — RetroArch's own config. Set it for an arcade-only one (shader, bezel); the arcade binds are layered over it |
| `MENU_CMD` | only used outside the shell: `wofi --dmenu`, then `rofi -dmenu`, then `fuzzel --dmenu` |
| `TITLES_FILE` | `~/.config/omarchy/arcade-titles.tsv` |
| `CACHE_FILE` | `~/.cache/omarchy/arcade-titles.cache.tsv` |
| `LOG_FILE` | `~/.cache/omarchy/arcade.log` |
| `ARTWORK` | `on` — set to `off` to never fetch artwork |
| `ART_KINDS` | `titles snaps boxarts` |
| `ART_DIR` | `~/.cache/omarchy/arcade-art` |
| `TILE_SIZE` | `300` — the width a game tile aims for, in pixels (overlay only) |
| `MAX_COLUMNS` | `6` — most tiles in one row (overlay only) |
| `SORT_BY` | `last played` — the wall's order: `last played`, `favourites`, `most played`, `name` or `year` (overlay only) |
| `GROUP_VERSIONS` | `on` — one tile per game, `Tab` for its other versions; `off` shows each romset on its own (overlay only) |

### From the panel

`Alt+S` opens the same settings inside the overlay, one row per key, and the
gear in the header does the same with a pointer. `←` `→` change a choice or a
number in place, `Enter` edits a path or a line of text, `Delete` puts a row
back to its default and `Esc` returns to the wall. `F5` re-reads the file, on
the wall as well as in the editor, so a hand edit lands without reopening.

A row is marked with a dot when the value is the config file's rather than a
default, and the line under the footer says where the value came from —
`set here`, `autodetected`, `default`, or `from the environment` for a key that
was exported for this run of the shell.

Two rows are lists rather than typed paths, because the answer is one of a
handful of files on this machine: **libretro core** offers every arcade core
installed, and **menu command** the dmenu programs that are actually here, both
led by an empty entry that means "autodetect". A path that is not there —
a mistyped ROM directory, a core that has been uninstalled — is shown in the
accent colour with `no such directory` under the footer, so the mistake is
visible in the row that made it rather than as a library that lists nothing.

Editing a row writes that one key to `arcade.conf` and nothing else: comments
and hand-written lines stay where they are, a setting written for the first
time lands under the commented example that describes it, and `Delete` removes
the line rather than writing a default into it. The file remains the source of
truth, so editing it by hand is still the same thing as editing it here — the
panel re-reads it every time it opens.

`TILE_SIZE`, `MAX_COLUMNS`, `SORT_BY` and `GROUP_VERSIONS` are the overlay's own: the launcher does not use
them, but they live in the same file so there is one place arcade settings are
kept and one editor for them. Changing any of them re-lays out the wall immediately.

The launcher exposes the same two operations for scripts:

```bash
arcade-launcher --settings              # "KEY<TAB>value<TAB>source<TAB>state"
arcade-launcher --set TILE_SIZE=240     # write one; several pairs are allowed
arcade-launcher --set TILE_SIZE=        # remove the line, back to the default
```

`source` is `file`, `env`, `auto` or `default`; `state` is `ok` or `missing`.
`--settings` also prints an `OPTIONS_<KEY>` line, tab separated, for the rows
that are lists. Values are written double-quoted, so `$HOME` keeps expanding
the way the shipped example does, while quotes, backslashes, backticks and
`$(…)` are escaped: the file is sourced, and a directory name is not a
program.

## Controls

RetroArch's own binds put **insert coin on right shift** and start on enter,
which is nobody's memory of an arcade cabinet. The **Controls** section of the
settings fixes that, and the first row does it in one press:

| Layout | Coin | Start | Stick | Buttons 1-6 |
| --- | --- | --- | --- | --- |
| **MAME standard** | `5` | `1` | arrows | `Ctrl` `Alt` `Space` `Shift` `Z` `X` |
| **RetroArch default** | `RShift` | `Enter` | arrows | `Z` `X` `A` `S` `W` `Q` |

Under it is a row per control — coin, start, the four directions, buttons 1 to
6, player two's coin and start, and the exit, pause and menu hotkeys. Select
one, press `Enter`, then **press the key you want**; `Esc` cancels rather than
binding, which is also why `Esc` stays RetroArch's own way out of a game.
`Delete` hands a control back to whatever your RetroArch config binds it to.

Buttons are numbered the way FBNeo numbers them in its default ("Classic")
layout: a game's Button 1 is the RetroPad's **B**, then **A**, **Y**, **X**,
**R**, **L**. Fighting games with three punches and three kicks are the one
exception: FBNeo puts the punches on the top row (`Y` `X` `L`) and the kicks on
the bottom (`B` `A` `R`), so the test below names both. Up to 1.2.0 the panel
numbered buttons for fighting games only, which put the MAME layout's `Ctrl`
on most games' Button 3. A saved MAME layout is renumbered automatically.

### Your stick

The **Controller** section of the settings shows the game controller RetroArch
will give player 1, the RetroArch profile it matches, and a verdict:

- **RetroArch set it up as player 1 at the last launch**: RetroArch's own log
  said so (`[Autoconf] … configured in port 1`) the last time a game started.
  That is the confirmation.
- **Start a game once to confirm**: the stick is plugged in and RetroArch has a
  profile for it, but no game has been started with it yet.
- **A problem**, in the accent colour: nothing plugged in, no RetroArch profile
  for it (games would not know its buttons), or a lever that reports as an
  analog stick. FBNeo ignores the analog stick, so the lever does nothing in
  games; set the stick's switch to D-pad.

Every control row also says which stick button does that job, for example
`Insert coin  Right Shift · stick: Minus`.

**Test the stick** opens a live board. Press anything on the stick and the
panel says what it does in a game — `B → Button 1`, and `Light Kick` in
3-punch, 3-kick fighters — while the matching tile lights up for as long as
it is held. A button that lights nothing is called out: not bound in RetroArch,
not used by arcade games (`ZL`, the stick clicks), or the analog stick. `Esc`,
or holding Home for a second, ends the test.

The test reads the stick directly (`bin/arcade-pad`, no root needed). It numbers
buttons the way RetroArch's udev driver does and looks them up in the same
profile, so what it shows is what the game gets.

An 8BitDo Arcade Stick on its **S** switch presents as a Nintendo Switch Pro
Controller, and RetroArch's stock profile for it keeps Nintendo's letters. On
that setting RetroPad `B` is the stick's `B`, and the labels in the panel
match what is printed on the buttons.

```bash
arcade-launcher --controller            # PAD, PROFILE, BIND and SEEN lines, tab separated
arcade-launcher --controller --follow   # its presses as they happen
```

### Where the binds live

Not in your RetroArch. The panel writes the binds, and only the binds, to
`~/.config/omarchy/arcade-retroarch.cfg`. `arcade-launcher` hands that file to
RetroArch with `--appendconfig`, which loads it on top of RetroArch's own
config for arcade games only. Your everyday setup keeps its own binds, and
everything else in it — shader, video driver, paths — applies to the arcade
too, including changes you make later.

The file also sets `config_save_on_exit` to `false`. RetroArch saves its
config when it quits, and appended settings are part of what it saves, so
without that line one arcade session would write the arcade binds into your
everyday `retroarch.cfg`. Settings win when appended, so the line switches the
save off for arcade sessions only. If a hand edit drops the line, the launcher
puts it back before the next game starts. Delete the file to start over.

`RETROARCH_CONFIG`, if you set it, replaces RetroArch's config for arcade
games (`--config`), and the binds are layered over that instead.

Version 1.1.0 kept the binds in a full copy of `retroarch.cfg` and pointed
`RETROARCH_CONFIG` at it, which stopped later RetroArch changes from reaching
the arcade. The first run after upgrading cuts that copy down to the binds,
keeps the rest as `arcade-retroarch.cfg.bak`, and removes `RETROARCH_CONFIG`
again. It only does this when `RETROARCH_CONFIG` names that exact file; one
you chose yourself is left alone.

The same from a terminal:

```bash
arcade-launcher --controls                  # "control<TAB>key<TAB>source"
arcade-launcher --controls-preset mame      # or retroarch
arcade-launcher --set-control coin1=num5    # one control; empty = hand it back
```

`source` is `file` when the arcade binds file binds it, `retroarch` when the
bind is inherited from the RetroArch config underneath. Key names are RetroArch's: `num5` is the 5
on the number row, `keypad5` the one on the keypad, `ctrl` and `shift` the left
ones, `nul` unbound.

MAME needs romsets matching its own version and BIOS files in RetroArch's
system directory; FBNeo is the friendlier default for classic arcade sets.

```bash
echo 'CORE_PATH="/usr/lib/libretro/mame_libretro.so"' >> ~/.config/omarchy/arcade.conf
```

## The launcher on its own

The overlay is a front end. `bin/arcade-launcher` does the work and is usable
by itself — from a terminal, a script, or a plain Hyprland install with no
`omarchy-shell` at all:

```bash
arcade-launcher                  # wofi/rofi/fuzzel menu, then launch
arcade-launcher bublbobl         # launch directly by ROM name
arcade-launcher --list           # title, path, played, playing, db title, year, maker per ROM
arcade-launcher --doctor         # check the setup
arcade-launcher --rebuild-titles # refresh the cache
arcade-launcher --settings       # every setting, its value and where it came from
arcade-launcher --set ARTWORK=off  # write a setting to arcade.conf
arcade-launcher --add pang.zip   # copy in, test-load, keep if it runs
```

RetroArch is detached with `setsid` (through `uwsm-app` when present) and its
verbose output is appended to `~/.cache/omarchy/arcade.log` with a timestamped
header per launch. Past 4 MB only the last megabyte is kept. If a game fails to
start, the notification quotes the part that matters, and the log has the
rest.

For plain Hyprland, [`hypr/hyprland.conf.snippet`](hypr/hyprland.conf.snippet)
has the window rules and a keybinding in classic `windowrulev2` syntax.

## Controller hotplug (optional)

With `omarchy-shell` you do not need this: the stick's Home button opens the
panel (see [With the stick](#with-the-stick)). These templates are for the
launcher on its own, on a plain Hyprland install, where plugging a stick in
opens the dmenu-style menu. They are in [`udev/`](udev), not installed by
`install.sh`:

```bash
sudo install -m644 udev/99-arcade-stick.rules /etc/udev/rules.d/99-arcade-stick.rules
sudo udevadm control --reload-rules
install -Dm644 udev/arcade-launcher.service ~/.config/systemd/user/arcade-launcher.service
systemctl --user daemon-reload
```

Plug in a stick and the menu appears. udev runs as root with no Wayland access,
so the rule tags the device for systemd and systemd starts the user unit. One
controller usually registers several input devices, so the unit wraps the
launcher in `flock` — the first firing owns the menu, the rest are no-ops.

## Files

```
Arcade.qml                     the overlay: its state, keys and the launcher processes
GameTile.qml                   one game on the wall
Header.qml                     wordmark, search line, add / settings / count
Toolbar.qml                    the sort and filter chips
Wall.qml                       the grid of games, the empty note, a setup problem
SettingsList.qml               the editor rows, for the arcade and for one game
PadTest.qml                    the stick test
Footer.qml                     the info bar and keycaps, or the plain hints
Library.js                     parsing, versions, sorting, filters, search, formatting
Settings.js                    the arcade's settings and a game's own, as editor rows
Controls.js                    key names and the cabinet control rows
Pad.js                         the stick: its profile, its presses, what they do
test.js                        node test.js
test-launcher.sh               ./test-launcher.sh - the config and bind writers, in bash
manifest.json                  plugin manifest
bin/arcade-launcher            lists and launches; the panel's whole backend
bin/arcade-rdb-dump            libretro .rdb -> TSV extractor (python3, no deps)
bin/arcade-artwork             title-screen fetcher and cache (python3, no deps)
bin/arcade-pad                 finds the stick, matches RetroArch's profile, follows its presses
share/arcade-titles.tsv        title overrides, used until you have your own
share/arcade.conf.example      commented config template
hypr/hyprland.conf.snippet     plain-Hyprland window rules
udev/                          optional hotplug templates
install.sh                     shortcut + enable
uninstall.sh                   reverses install.sh
```

`arcade-rdb-dump` reads RetroArch's `.rdb` format directly: an 8-byte magic, a
big-endian offset to the metadata block, then a flat run of MessagePack maps. It
decodes only the subset the libretro databases use, so it runs on a stock
`python3` with nothing installed.
