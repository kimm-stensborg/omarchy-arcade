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
  does not ask again. `arcade-artwork --refresh <rom>` forgets that. Being
  offline is never a miss: nothing is recorded, and it is tried again next time.
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
