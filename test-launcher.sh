#!/usr/bin/env bash
# ./test-launcher.sh - the launcher's config and bind writers, its listing, and
# the artwork fetcher's idea of a miss. Runs against a throwaway $HOME with a
# stand-in retroarch and core, so nothing here touches the real setup or the
# network.

set -uo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
launcher="$here/bin/arcade-launcher"
artwork="$here/bin/arcade-artwork"

sandbox="$(mktemp -d)"
trap 'pkill -f -- "$sandbox" 2>/dev/null; rm -rf "$sandbox"' EXIT

export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_RUNTIME_DIR="$sandbox/run"
# A stand-in RetroArch under a name of its own, so a real one you have open is
# never taken for the tests' -- or closed by them.
export ARCADE_RETROARCH_BIN=fakearch
unset ARCADE_CONFIG ROM_DIR ROM_EXTS CORE_PATH RETROARCH_CONFIG MENU_CMD TITLES_FILE \
  CACHE_FILE LOG_FILE ARTWORK ART_KINDS ART_DIR TILE_SIZE MAX_COLUMNS SHIPPED_TITLES_FILE

mkdir -p "$sandbox/bin" "$XDG_RUNTIME_DIR" "$HOME/Games/roms" "$XDG_CONFIG_HOME/omarchy" "$XDG_CACHE_HOME/omarchy" \
  "$XDG_CONFIG_HOME/retroarch/cores"
# The launcher reports failures on the desktop too; a refusal the tests expect
# should not pop up there, so the notifiers and hyprctl write down what they
# were asked instead.
notes="$sandbox/notes"
focused="$sandbox/focused"
for stub in notify-send omarchy-notification-send; do
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$notes" >"$sandbox/bin/$stub"
done
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\n' "$focused" >"$sandbox/bin/hyprctl"
# uwsm-app execs its way down to the game, as the real one does.
printf '#!/bin/sh\n[ "$1" = -- ] && shift\nexec "$@"\n' >"$sandbox/bin/uwsm-app"

# The ROM decides how the game goes: good.zip starts, bad.zip is missing
# files and leaves RetroArch sitting in its menu the way FBNeo does, and
# crash.zip takes RetroArch down with it.
cat >"$sandbox/bin/fakearch" <<'FAKE'
#!/bin/bash
[[ -n "${ARCADE_TEST_ARGS-}" ]] && printf '%s\n' "$*" >>"$ARCADE_TEST_ARGS"
# A test load (--max-frames) runs a couple of frames and quits, as RetroArch
# does -- "Unloading game" included, which is not a failure there.
if [[ " $* " == *" --max-frames="* ]]; then
  case "${*: -1}" in
    *bad.zip) echo "[libretro ERROR] [FBNeo] ROM at index 0 with name 201-p1.p1 and CRC 0x1 is required"
              echo "[INFO] [Core] Geometry: 640x480, Aspect: 1.333, FPS: 60.00" ;;
    *latecrash.zip) echo "[INFO] [Core] Geometry: 256x224, Aspect: 1.333, FPS: 60.00"; kill -SEGV $$ ;;
    *crash.zip) exit 1 ;;
    *) echo "[INFO] [Core] Geometry: 256x224, Aspect: 1.333, FPS: 60.00" ;;
  esac
  echo "[INFO] [Core] Unloading game..."
  exit 0
fi
sleep 30 & nap=$!
trap 'echo "[INFO] [Core] Unloading game..."; kill $nap; exit 0' TERM
case "${*: -1}" in
  *good.zip) echo "[INFO] [Core] Geometry: 256x224, Aspect: 1.333, FPS: 60.00" ;;
  *bad.zip)
    for f in 201-p1.p1 201-s1.s1 201-c1.c1 201-c2.c2; do
      echo "[libretro ERROR] [FBNeo] ROM at index 0 with name $f and CRC 0x1 is required"
    done
    # FBNeo then boots its own "files are missing" screen, which reports a
    # picture like any game does.
    echo "[INFO] [Core] Geometry: 640x480, Aspect: 1.333, FPS: 60.00" ;;
  *crash.zip) kill $nap; exit 1 ;;
esac
wait $nap
FAKE
chmod +x "$sandbox/bin/"*
: >"$XDG_CONFIG_HOME/retroarch/cores/fbneo_libretro.so"
export PATH="$sandbox/bin:$PATH"
export ARCADE_TEST_ARGS="$sandbox/args"

conf="$XDG_CONFIG_HOME/omarchy/arcade.conf"
profile="$XDG_CONFIG_HOME/omarchy/arcade-retroarch.cfg"

passed=0
failed=0

check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    printf 'FAIL  %s\n      got:  %q\n      want: %q\n' "$name" "$got" "$want"
  fi
}

setting() { "$launcher" --settings | awk -F'\t' -v k="$1" '$1 == k { print $'"${2:-2}"' }'; }
control() { "$launcher" --controls | awk -F'\t' -v k="$1" '$1 == k { print $'"${2:-2}"' }'; }

# ------------------------------------------------------------------ settings

check "no config file means defaults" "$(setting TILE_SIZE 3)" "default"

"$launcher" --set TILE_SIZE=240
check "a set lands in the file" "$(grep -c '^TILE_SIZE=' "$conf")" "1"
check "and reads back as the file's" "$(setting TILE_SIZE 3)" "file"
check "with its value" "$(setting TILE_SIZE)" "240"

"$launcher" --set TILE_SIZE=260
check "a second set replaces the line rather than adding one" "$(grep -c '^TILE_SIZE=' "$conf")" "1"
check "with the new value" "$(setting TILE_SIZE)" "260"

"$launcher" --set TILE_SIZE=
check "an empty value removes the line" "$(grep -c '^TILE_SIZE=' "$conf")" "0"
check "and the default is back" "$(setting TILE_SIZE 3)" "default"

printf '# How wide a tile aims to be\n# MAX_COLUMNS="6"\n\nARTWORK="on"\n' >"$conf"
"$launcher" --set MAX_COLUMNS=4
check "a new setting lands under its commented example" \
  "$(sed -n 3p "$conf")" 'MAX_COLUMNS="4"'
check "the comment above it stays" "$(sed -n 2p "$conf")" '# MAX_COLUMNS="6"'
"$launcher" --set MAX_COLUMNS=
check "and resetting it leaves the explanation behind" "$(grep -c 'MAX_COLUMNS' "$conf")" "1"

check "the environment is told apart from the file" \
  "$(MAX_COLUMNS=3 "$launcher" --settings | awk -F'\t' '$1 == "MAX_COLUMNS" { print $3 }')" "env"

marker="$sandbox/ran"
hostile='a`touch '"$marker"'`b $(touch '"$marker"') "q" \x'
"$launcher" --set ROM_DIR="$hostile"
# shellcheck source=/dev/null
got="$(source "$conf"; printf '%s' "$ROM_DIR")"
check "a value is written as text, never as a command" "$([[ -e "$marker" ]] && echo ran || echo inert)" "inert"
check "and reads back exactly" "$got" "$hostile"
"$launcher" --set ROM_DIR=

"$launcher" --set 'ROM_DIR=$HOME/Games/roms'
check "\$HOME in a value still expands" "$(setting ROM_DIR)" "$HOME/Games/roms"
"$launcher" --set ROM_DIR=

"$launcher" --set 'lower=x' 2>/dev/null
check "a key that is not a setting name is refused" "$?" "64"

check "a missing directory is flagged" \
  "$(ROM_DIR=/nowhere "$launcher" --settings | awk -F'\t' '$1 == "ROM_DIR" { print $4 }')" "missing"

# ------------------------------------------------------------------- listing

cache="$XDG_CACHE_HOME/omarchy/arcade-titles.cache.tsv"
printf '%s\t%s\t\t\n' \
  bublbobl "Bubble Bobble" \
  pgm "PGM (Polygame Master) System BIOS" \
  nmk004 "NMK004 Internal ROM" \
  neogeo "Neo Geo" \
  sfiiin "Street Fighter III: New Generation (Asia 970204, NO CD, bios set 1)" \
  snowbroj "Snow Bros. - Nick _ Tom (Japan)" \
  >"$cache"
touch "$cache"
for rom in bublbobl pgm nmk004 neogeo sfiiin snowbroj mystery; do : >"$HOME/Games/roms/$rom.zip"; done

list="$("$launcher" --list | cut -f1 | tr '\n' '|')"
check "games are listed and BIOS sets are not" "$list" \
  "Bubble Bobble|mystery|Snow Bros. - Nick & Tom (Japan)|Street Fighter III: New Generation (Asia 970204, NO CD, bios set 1)|"
check "the database title rides along for grouping, as written" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /snowbroj/ { print $5 }')" "Snow Bros. - Nick _ Tom (Japan)"

printf 'neogeo\tNeo Geo Test Menu\n' >"$XDG_CONFIG_HOME/omarchy/arcade-titles.tsv"
check "a title of your own brings a listed BIOS set back" \
  "$("$launcher" --list | cut -f1 | grep -c '^Neo Geo Test Menu$')" "1"
rm "$XDG_CONFIG_HOME/omarchy/arcade-titles.tsv"

# ---------------------------------------------------------------- favourites

favs="$XDG_CONFIG_HOME/omarchy/arcade-favourites"
starred() { "$launcher" --list | awk -F'\t' '$8 == "favourite" { print $1 }' | tr '\n' '|'; }
check "nothing is starred to begin with" "$(starred)" ""
"$launcher" --favourite bublbobl "$HOME/Games/roms/mystery.zip" bublbobl
check "starring by name or path, each once" "$(tr '\n' '|' <"$favs")" "bublbobl|mystery|"
check "and the listing says so" "$(starred)" "Bubble Bobble|mystery|"
"$launcher" --unfavourite mystery
check "unstarring takes it out again" "$(tr '\n' '|' <"$favs")" "bublbobl|"
"$launcher" --unfavourite mystery
check "unstarring what is not starred is fine" "$?" "0"
"$launcher" --favourite 'two words' 2>/dev/null
check "a name with a space is refused" "$?" "64"
"$launcher" --favourite 2>/dev/null
check "so is no name at all" "$?" "64"
"$launcher" --unfavourite bublbobl

# ------------------------------------------------------------- game facts

check "a game's genre, players and screen come from the shipped table" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /bublbobl/ { print $10 "|" $11 "|" $12 }')" "Platform|2|horizontal"
check "a romset the table does not know has none" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /mystery/ { print $10 "|" $11 "|" $12 "|" $14 }')" "|||"
check "a parent set is its own family" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /bublbobl/ { print $14 }')" "bublbobl"
check "and a launcher run through a symlink still finds the table" \
  "$(ln -s "$launcher" "$sandbox/bin/linked-launcher"; "$sandbox/bin/linked-launcher" --list | awk -F'\t' '$2 ~ /bublbobl/ { print $10 }')" "Platform"

# ------------------------------------------------ beyond your collection

all="$("$launcher" --list --all)"
known_here="$(awk -F'\t' '$15 == "" && $14 != ""' <<<"$all" | wc -l | tr -d ' ')"
check "--all adds every game FinalBurn Neo knows that is not here" \
  "$(awk -F'\t' '$15 == "missing"' <<<"$all" | wc -l | tr -d ' ')" "$(($(grep -vc '^#' "$here/share/arcade-gameinfo.tsv") - known_here))"
check "the one you have is not listed twice" \
  "$(awk -F'\t' '$2 ~ /\/bublbobl\.zip$/ || $2 == "bublbobl"' <<<"$all" | wc -l | tr -d ' ')" "1"
check "a game you do not have keeps its ROM name for a path, and its family" \
  "$(awk -F'\t' '$2 == "bublboblr" { print $14 "|" $15 }' <<<"$all")" "bublbobl|missing"
check "and a title of its own, from FBNeo when the database has none" \
  "$(awk -F'\t' '$2 == "19yy" { print $1 }' <<<"$all")" "19YY"
check "the plain listing is only what is here" "$("$launcher" --list | awk -F'\t' '$15 == "missing"' | wc -l | tr -d ' ')" "0"
"$launcher" --favourite galaga
check "a favourite you do not have yet comes along, marked" \
  "$("$launcher" --list | awk -F'\t' '$2 == "galaga" { print $8 "|" $15 }')" "favourite|missing"
"$launcher" --unfavourite galaga

# ------------------------------------------------------------ the library check

checkdir="$sandbox/checkroms"
mkdir -p "$checkdir"
printf 'g' >"$checkdir/good.zip"
printf 'b' >"$checkdir/bad.zip"
out="$(ROM_DIR="$checkdir" "$launcher" --check)"
check "each game is announced as it is checked" "$(grep -c '^checking' <<<"$out")" "2"
check "one that starts is ok" "$(grep -c "^ok"$'\t'"$checkdir/good.zip" <<<"$out")" "1"
check "one that does not says why" "$(grep "^broken" <<<"$out" | cut -f3)" "1 file is missing from the romset (201-p1.p1) -- it may be for another version, or need its BIOS."
check "the listing carries the reason" \
  "$(ROM_DIR="$checkdir" "$launcher" --list | awk -F'\t' '$2 ~ /bad.zip$/ { print ($13 != "") } $2 ~ /good.zip$/ { print ($13 == "") }' | tr -d '\n')" "11"
out="$(ROM_DIR="$checkdir" "$launcher" --check)"
check "a second check remembers rather than loading again" "$(grep -c '^checking' <<<"$out"),$(grep -c '^known-' <<<"$out")" "0,2"
check "--all loads them again" "$(ROM_DIR="$checkdir" "$launcher" --check --all | grep -c '^checking')" "2"
sleep 1; printf 'g2' >"$checkdir/bad.zip"
check "a romset replaced since is not known any more" \
  "$(ROM_DIR="$checkdir" "$launcher" --list | awk -F'\t' '$2 ~ /bad.zip$/ { print "[" $13 "]" }')" "[]"
check "a name that is not there is said so" "$(ROM_DIR="$checkdir" "$launcher" --check nosuchgame | cut -f1,3)" "broken"$'\t'"no such romset"
printf 'l' >"$checkdir/latecrash.zip"
check "a game that crashes once it is running is caught" \
  "$(ROM_DIR="$checkdir" "$launcher" --check latecrash | grep '^broken' | cut -f3)" "RetroArch crashed while running it (signal 11)."
rm -f "$XDG_STATE_HOME/omarchy/arcade-check.tsv"

# ------------------------------------------------------------- game settings

game() { "$launcher" --game "$1" | awk -F'\t' -v k="$2" '$1 == k { print $2 "|" $3 }'; }
gbind() { "$launcher" --game "$1" | awk -F'\t' -v k="$2" '$1 == "BIND" && $2 == k { print $3 "|" $4 }'; }
gcfg="$XDG_CONFIG_HOME/omarchy/arcade-games/bublbobl.cfg"
check "an untouched game has its database title" "$(game bublbobl TITLE)" "Bubble Bobble|default"
check "and RetroArch decides its picture" "$(game bublbobl SMOOTH)" "|default"
check "and no file of its own" "$([[ -e "$gcfg" ]] && echo yes || echo no)" "no"

"$launcher" --game-set bublbobl TITLE="Bubble Bobble (my way)"
check "a title of its own" "$(game bublbobl TITLE)" "Bubble Bobble (my way)|game"
check "is the title the wall shows" "$("$launcher" --list | awk -F'\t' '$2 ~ /bublbobl/ { print $1 }')" "Bubble Bobble (my way)"
"$launcher" --game-set bublbobl TITLE=
check "an empty title gives the database's back" "$(game bublbobl TITLE)" "Bubble Bobble|default"

"$launcher" --game-set bublbobl SMOOTH=smooth ASPECT=4:3 INTEGER=on ROTATE=90
check "picture settings read back" \
  "$(game bublbobl SMOOTH),$(game bublbobl ASPECT),$(game bublbobl INTEGER),$(game bublbobl ROTATE)" \
  "smooth|game,4:3|game,on|game,90|game"
check "as RetroArch keys" "$(grep -c '^video_smooth = "true"$\|^aspect_ratio_index = "0"$\|^video_rotation = "1"$' "$gcfg")" "3"
check "the file never saves into RetroArch's own config" "$(grep -c '^config_save_on_exit = "false"$' "$gcfg")" "1"
"$launcher" --game-set bublbobl ASPECT=
check "a reset takes the line out" "$(grep -c 'aspect_ratio' "$gcfg")" "0"
"$launcher" --game-set bublbobl ASPECT=wide 2>/dev/null
check "an unknown value is refused" "$?" "64"

check "controls start as the shared ones" "$(gbind bublbobl b1 | cut -d'|' -f2)" "shared"
"$launcher" --game-set bublbobl b1=space
check "one control of its own" "$(gbind bublbobl b1)" "space|game"
check "the rest stay shared" "$(gbind bublbobl b2 | cut -d'|' -f2)" "shared"
check "and the arcade binds are untouched" "$(cat "$profile" 2>/dev/null | grep -c 'input_player1_b = "space"')" "0"
"$launcher" --game-set bublbobl nosuch=x 2>/dev/null
check "a key that is not a setting is refused" "$?" "64"

check "no shader preset outside the shader directory" \
  "$("$launcher" --game-set bublbobl SHADER=../../etc/passwd 2>/dev/null; echo $?)" "64"
"$launcher" --game-set bublbobl SHADER=none
check "no shader at all" "$(game bublbobl SHADER),$(grep -c 'video_shader_enable = "false"' "$gcfg")" "none|game,1"

art="$XDG_CACHE_HOME/omarchy/arcade-art"
mkdir -p "$art"
printf 'old' >"$art/bublbobl.png"
"$launcher" --game-set bublbobl ART=snaps
check "another kind of artwork drops the cached picture" "$([[ -e "$art/bublbobl.png" ]] && echo kept || echo gone)" "gone"
printf 'not an image' >"$sandbox/fake.png"
"$launcher" --game-image bublbobl "$sandbox/fake.png" 2>/dev/null
check "only a real picture is taken" "$?" "64"
printf '\x89PNG\r\n\x1a\nrest' >"$sandbox/mine.png"
"$launcher" --game-image bublbobl "$sandbox/mine.png"
check "a picture of your own becomes the tile" "$(cmp -s "$sandbox/mine.png" "$art/bublbobl.png" && echo same)" "same"
check "and is marked as yours" "$(game bublbobl ART)" "custom|game"

# good.zip is launched further down; its own file should go with it.
"$launcher" --game-set good SMOOTH=sharp

# ------------------------------------------------------------------ controls

check "an untouched setup is RetroArch's layout" "$(control PRESET)" "retroarch"
check "with RetroArch's own coin key" "$(control coin1)" "rshift"
check "which says it is RetroArch's default" "$(control coin1 3)" "default"

printf 'video_driver = "vulkan"\ninput_exit_emulator = "f10"\n' >"$XDG_CONFIG_HOME/retroarch/retroarch.cfg"
check "a bind in your RetroArch config is read from there" "$(control exit 3)" "retroarch"

"$launcher" --controls-preset mame
check "a layout makes the arcade binds file" "$([[ -f "$profile" ]] && echo yes)" "yes"
check "holding binds, not a copy of your RetroArch config" "$(grep -c '^video_driver' "$profile")" "0"
check "and the line that keeps them out of your everyday config" \
  "$(grep -c '^config_save_on_exit = "false"' "$profile")" "1"
check "RETROARCH_CONFIG is left alone" "$(setting RETROARCH_CONFIG 3)" "default"
check "the profile matches the layout" "$(control PRESET)" "mame"
check "coin is 5" "$(control coin1)" "num5"
check "Button 1 is Ctrl, on the RetroPad B that FBNeo gives Button 1" \
  "$(grep -c '^input_player1_b = "ctrl"' "$profile")" "1"
check "Button 3 is Space, on Y" "$(grep -c '^input_player1_y = "space"' "$profile")" "1"
check "a bind is written once" "$(grep -c '^input_player1_select' "$profile")" "1"

"$launcher" --set-control coin1=num9
check "one control can be changed" "$(control coin1)" "num9"
check "which makes the layout a custom one" "$(control PRESET)" "custom"

"$launcher" --set-control coin1=
check "an empty bind hands it back" "$(grep -c '^input_player1_select' "$profile")" "0"
check "to RetroArch's default" "$(control coin1)" "rshift"

"$launcher" --set-control nope=x 2>/dev/null
check "an unknown control is refused" "$?" "64"

# Up to 1.2.0 Button 1 was Y, so a saved MAME layout had Ctrl on Y.
printf '%s\n' 'config_save_on_exit = "false"' \
  'input_player1_y = "ctrl"' 'input_player1_x = "alt"' 'input_player1_l = "space"' \
  'input_player1_b = "shift"' 'input_player1_a = "z"' 'input_player1_r = "x"' >"$profile"
"$launcher" --settings >/dev/null
bound() { grep "^input_player1_$1 = " "$profile" | cut -d'"' -f2; }
check "an old MAME layout is renumbered" \
  "$(bound b) $(bound a) $(bound y) $(bound x) $(bound r) $(bound l)" "ctrl alt space shift z x"
check "and still reads as MAME standard" "$(control PRESET)" "mame"
printf '%s\n' 'input_player1_y = "ctrl"' >"$profile"
"$launcher" --settings >/dev/null
check "a layout of your own is not touched" "$(cat "$profile")" 'input_player1_y = "ctrl"'
rm -f "$profile"

# 1.1.0 kept the binds in a full copy of retroarch.cfg and pointed
# RETROARCH_CONFIG at it.
cp "$XDG_CONFIG_HOME/retroarch/retroarch.cfg" "$profile"
printf 'input_player1_select = "num5"\nconfig_save_on_exit = "false"\n' >>"$profile"
"$launcher" --set RETROARCH_CONFIG="$profile"
"$launcher" --settings >/dev/null
check "an old full copy is cut down to the binds" "$(grep -c '^video_driver' "$profile")" "0"
check "keeping them" "$(control coin1)" "num5"
check "with the rest set aside, not lost" "$(grep -c '^video_driver = "vulkan"' "$profile.bak")" "1"
check "and RETROARCH_CONFIG handed back" "$(setting RETROARCH_CONFIG 3)" "default"

own="$sandbox/my-arcade.cfg"
printf 'video_driver = "gl"\n' >"$own"
"$launcher" --set RETROARCH_CONFIG="$own"
"$launcher" --settings >/dev/null
check "a RETROARCH_CONFIG chosen by hand is kept" "$(setting RETROARCH_CONFIG)" "$own"
check "and never cut down" "$(cat "$own")" 'video_driver = "gl"'
check "binds it does not set come from it" \
  "$(printf 'input_player1_start = "num7"\n' >>"$own"; "$launcher" --set-control start1=; control start1)" "num7"
"$launcher" --set RETROARCH_CONFIG=

# ------------------------------------------------------------------- artwork

misses="$(ART="$artwork" DIR="$sandbox/art" python3 - <<'EOF'
import importlib.machinery, importlib.util, os, urllib.error
loader = importlib.machinery.SourceFileLoader("arcade_artwork", os.environ["ART"])
spec = importlib.util.spec_from_loader("arcade_artwork", loader)
art = importlib.util.module_from_spec(spec)
loader.exec_module(art)
d = os.environ["DIR"]
os.makedirs(d)

def offline(url):
    raise urllib.error.URLError("no network")
def not_there(url):
    raise urllib.error.HTTPError(url, 404, "Not Found", None, None)
def busy(url):
    raise urllib.error.HTTPError(url, 503, "Unavailable", None, None)

for rom, fetch in (("offline", offline), ("absent", not_there), ("busy", busy)):
    art.download = fetch
    art.fetch_one(rom, "Some Game", d, ["titles"])
print(" ".join(sorted(f for f in os.listdir(d) if f.endswith(".miss"))))
EOF
)"
check "only a 404 everywhere is recorded as a miss" "$misses" "absent.miss"

# ----------------------------------------------------------------- the stick

# Profiles are matched the way RetroArch matches them, against a folder of
# made-up ones, so the answer does not depend on what is plugged in here.
matched="$(PAD="$here/bin/arcade-pad" DIR="$sandbox/autoconfig" python3 - <<'EOF'
import importlib.machinery, importlib.util, os
loader = importlib.machinery.SourceFileLoader("arcade_pad", os.environ["PAD"])
spec = importlib.util.spec_from_loader("arcade_pad", loader)
pad = importlib.util.module_from_spec(spec)
loader.exec_module(pad)
d = os.environ["DIR"]
os.makedirs(os.path.join(d, "udev"))

def profile(name, text):
    with open(os.path.join(d, "udev", name), "w") as fh:
        fh.write(text)

profile("by-name.cfg", 'input_driver = "udev"\ninput_device = "Nintendo Co., Ltd. Pro Controller"\n')
profile("by-ids.cfg", 'input_driver = "udev"\ninput_device = "Pro Controller"\n'
        'input_device_alt1 = "Nintendo Co., Ltd. Pro Controller"\n'
        'input_vendor_id = "1406"\ninput_product_id = "8201"\n')
profile("off.cfg", '#input_device = "Nintendo Co., Ltd. Pro Controller"\n')
stick = {"name": "Nintendo Co., Ltd. Pro Controller", "vendor": 0x057E, "product": 0x2009}
other = {"name": "Mystery Pad", "vendor": 1, "product": 2}
print(os.path.basename(pad.autoconfig(stick, [d])[0]), pad.autoconfig(other, [d]))
EOF
)"
check "the profile matching name and ids wins, as in RetroArch" "$matched" "by-ids.cfg None"

# ----------------------------------------------------------------- launching

# The stand-in writes down how it was started.
sed -i 's|^sleep 30 \& nap=\$!|printf "%s\\n" "$*" >>"'"$sandbox"'/started"\nsleep 30 \& nap=$!|' "$sandbox/bin/fakearch"

# Waits up to five seconds for a condition, since the launch is watched from
# the side and reports after the launcher has already returned.
eventually() {
  local tries=0
  until eval "$1"; do
    ((tries++ < 50)) || return 1
    sleep 0.1
  done
}
games_running() { pgrep -fc -- "$sandbox/bin/fakearch" || true; }
running_pid() { cut -f1 "$XDG_RUNTIME_DIR/omarchy-arcade.running" 2>/dev/null; }
history="$XDG_STATE_HOME/omarchy/arcade-history.tsv"

for rom in good other bad crash; do : >"$HOME/Games/roms/$rom.zip"; done
: >"$notes"
: >"$focused"

"$launcher" good
check "a launch returns straight away" "$?" "0"
eventually '[[ "$(games_running)" == 1 ]]'
check "and the game is running" "$(games_running)" "1"
first="$(running_pid)"
check "under the pid the launcher wrote down" "$(kill -0 "$first" 2>/dev/null && echo alive)" "alive"
check "the play is remembered" "$(grep -c "good.zip" "$history")" "1"
check "the arcade's base, then the binds, then the game's own settings" \
  "$(grep -v -- '--max-frames' "$ARCADE_TEST_ARGS" | grep -c -- '--appendconfig [^ ]*/omarchy-arcade-base.cfg|[^ ]*arcade-retroarch.cfg|[^ ]*/arcade-games/good.cfg')" "1"
check "the base keeps RetroArch's crash-prone desktop window from being built" \
  "$(grep -c '^desktop_menu_enable = "false"$' "$XDG_RUNTIME_DIR/omarchy-arcade-base.cfg")" "1"
check "and is never saved into RetroArch's own config" \
  "$(grep -c '^config_save_on_exit = "false"$' "$XDG_RUNTIME_DIR/omarchy-arcade-base.cfg")" "1"
check "the listing says it is playing" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /good.zip$/ { print ($3 > 0) "," $4 }')" "1,playing"
sleep 1
check "a game that started says nothing" "$(cat "$notes")" ""

check "the arcade binds are layered over RetroArch's own config" \
  "$(grep -c -- "--appendconfig [^ ]*$profile" "$sandbox/started")" "1"
check "rather than replacing it" "$(grep -c -- "--config" "$sandbox/started")" "0"

"$launcher" good
check "launching it again starts no second copy" "$(games_running)" "1"
check "it brings the running one forward" "$(grep -c "pid:$first" "$focused")" "1"
check "and counts as playing it again" "$(grep -c "good.zip" "$history")" "2"
check "the listing counts the plays" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /good.zip$/ { print $9 }')" "2"
# A history folded down to one line per game keeps its count.
cp "$history" "$sandbox/history.keep"
printf '1\t%s\t5\n' "$HOME/Games/roms/good.zip" >>"$history"
check "a folded line carries its plays" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /good.zip$/ { print $9 }')" "7"
cp "$sandbox/history.keep" "$history"

"$launcher" other
eventually '! kill -0 "$first" 2>/dev/null'
check "another game closes the one running" "$(kill -0 "$first" 2>/dev/null && echo alive || echo closed)" "closed"
check "and runs in its place" "$(games_running)" "1"
check "which is now the one playing" "$(cut -f2 "$XDG_RUNTIME_DIR/omarchy-arcade.running")" "$HOME/Games/roms/other.zip"

"$launcher" bad
eventually 'grep -q "did not start" "$notes"'
check "a romset with files missing is reported" "$(grep -c "bad did not start" "$notes")" "1"
check "saying how many and which" \
  "$(grep -o '4 files are missing from the romset (201-p1.p1, 201-s1.s1, 201-c1.c1, ...)' "$notes")" \
  "4 files are missing from the romset (201-p1.p1, 201-s1.s1, 201-c1.c1, ...)"
eventually '[[ "$(games_running)" == 0 ]]'
check "and RetroArch is not left sitting in its menu" "$(games_running)" "0"
check "a failed launch is not a game played" "$(grep -c "bad.zip" "$history")" "0"
check "nor the one running" "$([[ -e "$XDG_RUNTIME_DIR/omarchy-arcade.running" ]] && echo yes || echo no)" "no"

: >"$notes"
"$launcher" crash
eventually 'grep -q "did not start" "$notes"'
check "a crash on start is reported too" \
  "$(grep -c "crash did not start. RetroArch closed as soon as it started." "$notes")" "1"

# Home on the stick, in a game: --stop.
: >"$notes"
"$launcher" other
eventually '[[ "$(games_running)" == 1 ]]'
"$launcher" --stop
check "--stop closes the game the launcher started" "$?" "0"
check "and it is gone" "$(games_running)" "0"
check "and no longer the one playing" "$([[ -e "$XDG_RUNTIME_DIR/omarchy-arcade.running" ]] && echo yes || echo no)" "no"
sleep 1
check "a game closed on purpose is not reported as failing" "$(grep -c "did not start" "$notes")" "0"
"$launcher" --stop
check "with nothing running it says so" "$?" "1"

sed -i '/^config_save_on_exit/d' "$profile"
"$launcher" crash 2>/dev/null
check "a hand edit that dropped the save guard gets it back before a launch" \
  "$(grep -c '^config_save_on_exit = "false"' "$profile")" "1"
sleep 0.5

# One not started by the launcher: yours to close, not the launcher's.
: >"$notes"
: >"$focused"
(exec -a fakearch "$sandbox/bin/fakearch" "$sandbox/mine.zip") >/dev/null 2>&1 &
mine=$!
eventually '[[ "$(games_running)" == 1 ]]'
"$launcher" good 2>/dev/null
check "a RetroArch the launcher did not start is refused" "$?" "72"
check "and left running" "$(kill -0 "$mine" 2>/dev/null && echo alive)" "alive"
check "with a reason on the desktop" "$(grep -c "RetroArch is already running" "$notes")" "1"
"$launcher" --stop
check "--stop leaves it alone too, and says why" "$?" "72"
check "still running" "$(kill -0 "$mine" 2>/dev/null && echo alive)" "alive"
kill "$mine" 2>/dev/null

# ------------------------------------------------------------ adding games

drop="$sandbox/Downloads"
mkdir -p "$drop"
printf 'fresh' >"$drop/freshgood.zip"
printf 'broken' >"$drop/freshbad.zip"
printf 'crashes' >"$drop/freshcrash.zip"
printf 'bios' >"$drop/qsound.zip"
printf 'hello' >"$drop/notes.txt"
before="$(ls "$HOME/Games/roms" | wc -l)"
added="$("$launcher" --add "$drop/freshgood.zip" "$drop/freshbad.zip" "$drop/freshcrash.zip" \
  "$drop/qsound.zip" "$drop/notes.txt" | grep -v '^checking' | cut -f1,2 | tr '\t\n' ' |')"
check "each dropped file gets a verdict" "$added" \
  "added freshgood.zip|rejected freshbad.zip|rejected freshcrash.zip|bios qsound.zip|skipped notes.txt|"
check "a game that runs is in the collection" "$(cat "$HOME/Games/roms/freshgood.zip")" "fresh"
check "one that does not is taken out again" \
  "$([[ -e "$HOME/Games/roms/freshbad.zip" || -e "$HOME/Games/roms/freshcrash.zip" ]] && echo left || echo gone)" "gone"
check "saying why" "$("$launcher" --add "$drop/freshbad.zip" | grep -v '^checking' | cut -f3)" \
  "1 file is missing from the romset (201-p1.p1) -- it may be for another version, or need its BIOS."
check "a BIOS goes in without being played" "$(cat "$HOME/Games/roms/qsound.zip")" "bios"
check "the original is left where it was" "$(cat "$drop/freshgood.zip")" "fresh"
check "nothing else went in" "$(ls "$HOME/Games/roms" | wc -l)" "$((before + 2))"
check "the same file again is already there" "$("$launcher" --add "$drop/freshgood.zip" | grep -v '^checking' | cut -f1)" "exists"
printf 'other' >"$drop/other.zip"
check "a different file of the same name is never replaced" \
  "$("$launcher" --add "$drop/other.zip" | grep -v '^checking' | cut -f1)$(cat "$HOME/Games/roms/other.zip" 2>/dev/null)" "conflict"
check "and no test load is left running" "$(games_running)" "0"

# Several at once: a folder stands for the romsets in it.
batch="$sandbox/batch"
mkdir -p "$batch/nested"
printf 'a' >"$batch/onegood.zip"
printf 'b' >"$batch/twogood.ZIP"
printf 'c' >"$batch/readme.txt"
printf 'd' >"$batch/nested/deepgood.zip"
out="$("$launcher" --add "$batch")"
check "each file is announced as it is checked, counted" \
  "$(grep '^checking' <<<"$out" | cut -f2- | tr '\t\n' ' |')" "onegood.zip 1 2|twogood.ZIP 2 2|"
check "a folder adds the romsets in it" "$(grep -v '^checking' <<<"$out" | cut -f1,2 | tr '\t\n' ' |')" \
  "added onegood.zip|added twogood.ZIP|"
check "but not the ones in folders inside it" "$([[ -e "$HOME/Games/roms/deepgood.zip" ]] && echo yes || echo no)" "no"

printf '\n'
if ((failed)); then
  printf '  %d failed, %d ok\n' "$failed" "$passed"
  exit 1
fi
printf '  ok  %d checks\n' "$passed"
