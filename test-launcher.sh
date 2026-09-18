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
trap 'rm -rf "$sandbox"' EXIT

export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
unset ARCADE_CONFIG ROM_DIR ROM_EXTS CORE_PATH RETROARCH_CONFIG MENU_CMD TITLES_FILE \
  CACHE_FILE LOG_FILE ARTWORK ART_KINDS ART_DIR TILE_SIZE MAX_COLUMNS SHIPPED_TITLES_FILE

mkdir -p "$sandbox/bin" "$HOME/Games/roms" "$XDG_CONFIG_HOME/omarchy" "$XDG_CACHE_HOME/omarchy" \
  "$XDG_CONFIG_HOME/retroarch/cores"
# The launcher reports failures on the desktop too; a refusal the tests expect
# should not pop up there.
for stub in retroarch notify-send omarchy-notification-send; do
  printf '#!/bin/sh\nexit 0\n' >"$sandbox/bin/$stub"
  chmod +x "$sandbox/bin/$stub"
done
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
  >"$cache"
touch "$cache"
for rom in bublbobl pgm nmk004 neogeo sfiiin mystery; do : >"$HOME/Games/roms/$rom.zip"; done

list="$("$launcher" --list | cut -f1 | tr '\n' '|')"
check "games are listed and BIOS sets are not" "$list" \
  "Bubble Bobble|mystery|Street Fighter III: New Generation (Asia 970204, NO CD, bios set 1)|"

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
check "a layout makes the arcade profile" "$([[ -f "$profile" ]] && echo yes)" "yes"
check "copied from your RetroArch config" "$(grep -c '^video_driver = "vulkan"' "$profile")" "1"
check "which cannot rewrite itself on exit" "$(grep -c '^config_save_on_exit = "false"' "$profile")" "1"
check "and is what RetroArch will be told to use" "$(setting RETROARCH_CONFIG)" "$profile"
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

printf '\n'
if ((failed)); then
  printf '  %d failed, %d ok\n' "$failed" "$passed"
  exit 1
fi
printf '  ok  %d checks\n' "$passed"
