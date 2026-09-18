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
printf '%s\t%s\n' \
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
check "a bind is written once" "$(grep -c '^input_player1_select' "$profile")" "1"

"$launcher" --set-control coin1=num9
check "one control can be changed" "$(control coin1)" "num9"
check "which makes the layout a custom one" "$(control PRESET)" "custom"

"$launcher" --set-control coin1=
check "an empty bind hands it back" "$(grep -c '^input_player1_select' "$profile")" "0"
check "to RetroArch's default" "$(control coin1)" "rshift"

"$launcher" --set-control nope=x 2>/dev/null
check "an unknown control is refused" "$?" "64"

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
check "the listing says it is playing" \
  "$("$launcher" --list | awk -F'\t' '$2 ~ /good.zip$/ { print ($3 > 0) "," $4 }')" "1,playing"
sleep 1
check "a game that started says nothing" "$(cat "$notes")" ""

check "the arcade binds are layered over RetroArch's own config" \
  "$(grep -c -- "--appendconfig $profile" "$sandbox/started")" "1"
check "rather than replacing it" "$(grep -c -- "--config" "$sandbox/started")" "0"

"$launcher" good
check "launching it again starts no second copy" "$(games_running)" "1"
check "it brings the running one forward" "$(grep -c "pid:$first" "$focused")" "1"
check "and counts as playing it again" "$(grep -c "good.zip" "$history")" "2"

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
kill "$mine" 2>/dev/null

printf '\n'
if ((failed)); then
  printf '  %d failed, %d ok\n' "$failed" "$passed"
  exit 1
fi
printf '  ok  %d checks\n' "$passed"
