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
| `Enter` | launch the selected game |
| `F5` | re-read the ROM directory |
| `Ctrl+,` | open the settings, controls included |
| `Esc` | close |

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
2. **`~/.cache/omarchy/arcade-titles.cache.tsv`** — generated from the libretro
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
`68` no core, `69` no menu program, `70` no RetroArch).

## Configuration

`~/.config/omarchy/arcade.conf` is a shell fragment; every key can also be set
in the environment for a single run. See
[`share/arcade.conf.example`](share/arcade.conf.example).

| Variable | Default |
| --- | --- |
| `ROM_DIR` | `~/Games/roms` (searched two levels deep) |
| `ROM_EXTS` | `zip 7z chd` |
| `CORE_PATH` | autodetected: FBNeo, then MAME, in `~/.config/retroarch/cores` then `/usr/lib/libretro` |
| `RETROARCH_CONFIG` | unset — RetroArch's own config. Set it for an arcade-only profile (shader, bezel, input binds) |
| `MENU_CMD` | only used outside the shell: `wofi --dmenu`, then `rofi -dmenu`, then `fuzzel --dmenu` |
| `TITLES_FILE` | `~/.config/omarchy/arcade-titles.tsv` |
| `CACHE_FILE` | `~/.cache/omarchy/arcade-titles.cache.tsv` |
| `LOG_FILE` | `~/.cache/omarchy/arcade.log` |
| `ARTWORK` | `on` — set to `off` to never fetch artwork |
| `ART_KINDS` | `titles snaps boxarts` |
| `ART_DIR` | `~/.cache/omarchy/arcade-art` |
| `TILE_SIZE` | `300` — the width a game tile aims for, in pixels (overlay only) |
| `MAX_COLUMNS` | `6` — most tiles in one row (overlay only) |

### From the panel

`Ctrl+,` opens the same settings inside the overlay, one row per key, and the
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

`TILE_SIZE` and `MAX_COLUMNS` are the overlay's own: the launcher does not use
them, but they live in the same file so there is one place arcade settings are
kept and one editor for them. Changing either re-lays out the wall immediately.

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
| **RetroArch default** | `RShift` | `Enter` | arrows | `A` `S` `Q` `Z` `X` `W` |

Under it is a row per control — coin, start, the four directions, buttons 1 to
6, player two's coin and start, and the exit, pause and menu hotkeys. Select
one, press `Enter`, then **press the key you want**; `Esc` cancels rather than
binding, which is also why `Esc` stays RetroArch's own way out of a game.
`Delete` hands a control back to whatever your RetroArch config binds it to.

Button numbering follows FBNeo's six-button arcade panel, which RetroArch lays
out as `Y X L` over `B A R` — button 1 is the RetroPad's Y.

### Where the binds live

Not in your RetroArch. The panel writes an arcade-only profile —
`~/.config/omarchy/arcade-retroarch.cfg` unless `RETROARCH_CONFIG` already
names one — and points `RETROARCH_CONFIG` at it, so `arcade-launcher` passes it
to RetroArch with `--config` and your everyday setup keeps its own binds.

`--config` *replaces* RetroArch's configuration rather than layering over it, so
a profile holding nothing but binds would throw away your video driver, paths
and everything else. The profile is therefore made as a **copy of your
RetroArch config**, with only the binds changed afterwards, and
`config_save_on_exit` pinned to `false` so a session cannot quietly rewrite the
binds on its way out. Delete the file to start over; the panel rebuilds it from
your RetroArch config the next time a control is set.

The same from a terminal:

```bash
arcade-launcher --controls                  # "control<TAB>key<TAB>source"
arcade-launcher --controls-preset mame      # or retroarch
arcade-launcher --set-control coin1=num5    # one control; empty = hand it back
```

`source` is `file` when the arcade profile binds it, `retroarch` when the bind
is inherited from your own config. Key names are RetroArch's: `num5` is the 5
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
arcade-launcher --list           # "title<TAB>path" for every ROM found
arcade-launcher --doctor         # check the setup
arcade-launcher --rebuild-titles # refresh the cache
arcade-launcher --settings       # every setting, its value and where it came from
arcade-launcher --set ARTWORK=off  # write a setting to arcade.conf
```

RetroArch is detached with `setsid` (through `uwsm-app` when present) and its
output is appended to `~/.cache/omarchy/arcade.log` with a timestamped header
per launch. If a game fails to start, that log is the first place to look.

For plain Hyprland, [`hypr/hyprland.conf.snippet`](hypr/hyprland.conf.snippet)
has the window rules and a keybinding in classic `windowrulev2` syntax.

## Controller hotplug (optional)

Templates in [`udev/`](udev), not installed by `install.sh`:

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
Arcade.qml                     the overlay
Model.js                       parsing, matching, formatting - all of it tested
test.js                        node test.js
test-launcher.sh               ./test-launcher.sh - the config and bind writers, in bash
manifest.json                  plugin manifest
bin/arcade-launcher            lists and launches; the panel's whole backend
bin/arcade-rdb-dump            libretro .rdb -> TSV extractor (python3, no deps)
bin/arcade-artwork             title-screen fetcher and cache (python3, no deps)
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
