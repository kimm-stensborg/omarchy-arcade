#!/bin/bash

# Enable Arcade and bind a key to it.
#
#   ./install.sh                 pick a shortcut interactively
#   ./install.sh --key "SUPER + A"
#   ./install.sh --no-bind       just enable the plugin
#   ./install.sh --no-link       skip the ~/.local/bin/arcade-launcher symlink
#
# The shortcut proposed first is SUPER + A, unless Hyprland already has that
# combination, in which case the first free candidate is proposed instead.
# Whatever is proposed can be edited; Enter accepts it.

set -euo pipefail

ID="io.github.kimm-stensborg.arcade"
NAME="Arcade"
SRC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MARKER="-- Arcade overlay ($ID)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy"
BIN_DIR="$HOME/.local/bin"

# SUPER + A for arcade; free on a stock Omarchy. The rest are for when it is
# not.
CANDIDATES=(
  "SUPER + A"
  "SUPER + ALT + A"
  "SUPER + SHIFT + A"
  "SUPER + CTRL + A"
)

fail() {
  echo "install.sh: $*" >&2
  exit 1
}

note() { printf '  %s\n' "$*"; }

interactive() { [[ -t 0 && -t 1 ]]; }

for tool in jq hyprctl omarchy-shell; do
  command -v "$tool" >/dev/null || fail "$tool is required"
done

key=""
bind=1
link=1
while (($# > 0)); do
  case "$1" in
  --key)
    key="${2:-}"
    [[ -n $key ]] || fail "--key requires a shortcut"
    shift 2
    ;;
  --no-bind)
    bind=0
    shift
    ;;
  --no-link)
    link=0
    shift
    ;;
  -h | --help)
    sed -n '3,12p' "$0" | sed 's/^# \?//'
    exit 0
    ;;
  *) fail "unknown option: $1" ;;
  esac
done

# ---------------------------------------------------------------- the games

echo "Checking what the launcher needs"

command -v retroarch >/dev/null ||
  note "! retroarch is not installed - omarchy pkg add retroarch"

core=""
for dir in "$HOME/.config/retroarch/cores" /usr/lib/libretro /usr/local/lib/libretro; do
  for name in fbneo mame mame2003_plus mame2010 mame2016; do
    [[ -f "$dir/${name}_libretro.so" ]] && { core="$dir/${name}_libretro.so"; break 2; }
  done
done
[[ -n $core ]] && note "core: $core" ||
  note "! no arcade libretro core - omarchy pkg add libretro-fbneo-git"

# Seed the config and the title overrides, never overwriting what is there.
mkdir -p "$CONFIG_DIR" "$CACHE_DIR"
for pair in "arcade.conf.example:arcade.conf" "arcade-titles.tsv:arcade-titles.tsv"; do
  src="$SRC_DIR/share/${pair%%:*}"
  dst="$CONFIG_DIR/${pair##*:}"
  if [[ -e $dst ]]; then
    note "kept $dst"
  else
    install -m644 "$src" "$dst"
    note "created $dst"
  fi
done

# The overlay calls the script inside the plugin folder, so the symlink is only
# for using it from a terminal (--doctor, --list, launching by name).
if ((link)); then
  mkdir -p "$BIN_DIR"
  for script in arcade-launcher arcade-rdb-dump; do
    ln -sfn "$SRC_DIR/bin/$script" "$BIN_DIR/$script"
  done
  note "linked arcade-launcher into $BIN_DIR"
fi

"$SRC_DIR/bin/arcade-launcher" --rebuild-titles >/dev/null 2>&1 &&
  note "built the title cache" ||
  note "! could not build the title cache; titles fall back to filenames"

# Artwork downloads itself the first time the panel opens; doing it here too
# means that first open is already dressed. Backgrounded, because a large
# library should not hold up the install.
if command -v python3 >/dev/null && [[ ${ARTWORK:-on} != off ]]; then
  (
    "$SRC_DIR/bin/arcade-launcher" --list 2>/dev/null |
      cut -f2 | xargs -r -n1 basename | sed 's/\.[^.]*$//' |
      "$SRC_DIR/bin/arcade-artwork" >/dev/null 2>&1
  ) &
  note "fetching artwork in the background"
fi

# -------------------------------------------------------------- the shortcut

# "super+a" for any spelling of SUPER + A, so a combination can be compared
# against what Hyprland reports regardless of order or spacing.
normalize() {
  tr 'a-z' 'A-Z' <<<"$1" |
    tr -d ' ' | tr '+' '\n' |
    sed 's/^MOD$/SUPER/; s/^WIN$/SUPER/; s/^CONTROL$/CTRL/; s/^MOD1$/ALT/' |
    awk '
      /^(SUPER|SHIFT|CTRL|ALT)$/ { mods[$0] = 1; next }
      { key = $0 }
      END {
        split("SUPER SHIFT CTRL ALT", order, " ")
        for (i = 1; i <= 4; i++) if (order[i] in mods) out = out tolower(order[i]) "+"
        print out tolower(key)
      }'
}

# Every bound combination Hyprland currently knows, outside submaps, one per
# line in the same shape as normalize(). Binds carrying a keycode rather than a
# key name are skipped: they cannot collide with a combination typed as text.
bound_combos() {
  hyprctl binds -j | jq -r '
    def mods(m):
      [ if (m / 64 % 2) >= 1 then "super" else empty end,
        if (m % 2) >= 1 then "shift" else empty end,
        if (m / 4 % 2) >= 1 then "ctrl" else empty end,
        if (m / 8 % 2) >= 1 then "alt" else empty end ];
    .[]
    | select(.submap == "" and .key != "")
    | ((mods(.modmask) + [.key | ascii_downcase]) | join("+"))
      + "\t" + (.description // "")
  '
}

describe_conflict() {
  awk -F'\t' -v c="$1" '$1 == c && !found { found = 1; print $2 }' <<<"$TAKEN"
}

is_taken() {
  awk -F'\t' -v c="$1" 'BEGIN { rc = 1 } $1 == c { rc = 0 } END { exit rc }' <<<"$TAKEN"
}

pick_default() {
  local candidate
  for candidate in "${CANDIDATES[@]}"; do
    is_taken "$(normalize "$candidate")" || {
      printf '%s\n' "$candidate"
      return
    }
  done
  printf '%s\n' "${CANDIDATES[0]}"
}

# The block this script owns: the shortcut, plus the two window rules that make
# RetroArch open the way a cabinet would. Everything sits under one marker so
# re-running replaces it and uninstall.sh can lift it back out.
write_binding() {
  local combo="$1" conflict="$2"
  mkdir -p "$(dirname "$BINDINGS")"
  touch "$BINDINGS"
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"

  local tmp
  tmp=$(mktemp)
  awk -v marker="$MARKER" '
    $0 == marker { skip = 1; next }
    skip && NF == 0 { skip = 0; next }
    skip { next }
    { lines[++n] = $0 }
    END {
      while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
      for (i = 1; i <= n; i++) print lines[i]
    }
  ' "$BINDINGS" >"$tmp"
  mv "$tmp" "$BINDINGS"

  {
    printf '\n%s\n' "$MARKER"
    [[ -z $conflict ]] || printf 'hl.unbind("%s")\n' "$combo"
    printf 'o.bind("%s", "Arcade", "omarchy-shell shell toggle %s '"'"'{}'"'"'")\n' "$combo" "$ID"
    printf '%s\n' '-- RetroArch as a cabinet: present frames without waiting for vsync'
    printf '%s\n' '-- (lower latency, some tearing), and no open animation. Omarchy already'
    printf '%s\n' '-- opens it fullscreen and inhibits idle.'
    printf '%s\n' 'hl.config({ general = { allow_tearing = true } })'
    printf '%s\n' 'o.window("com.libretro.RetroArch", { immediate = true, no_anim = true })'
  } >>"$BINDINGS"

  hyprctl reload >/dev/null
  local errors
  errors=$(hyprctl configerrors)
  [[ -z ${errors//[[:space:]]/} || $errors == "no errors"* ]] ||
    fail "Hyprland reported config errors:"$'\n'"$errors"
}

# The combination an earlier run of this script bound, so re-running and keeping
# the same shortcut does not look like a collision with itself.
ours() {
  [[ -f $BINDINGS ]] || return 0
  awk -v marker="$MARKER" '
    $0 == marker { found = 1; next }
    found && /^o\.bind\(/ {
      match($0, /"[^"]+"/)
      print substr($0, RSTART + 1, RLENGTH - 2)
      exit
    }
  ' "$BINDINGS"
}

OURS=$(normalize "$(ours)")
TAKEN=$(bound_combos | awk -F'\t' -v ours="$OURS" '$1 != ours')

if [[ $bind == 1 ]]; then
  if [[ -z $key ]]; then
    interactive || fail "no shortcut given; pass --key \"SUPER + A\" or --no-bind"
    default=$(pick_default)
    if command -v gum >/dev/null; then
      key=$(gum input --header "Shortcut for $NAME (Enter to accept)" --value "$default") ||
        fail "cancelled"
    else
      read -rp "Shortcut for $NAME [$default]: " key
    fi
    key="${key:-$default}"
  fi

  combo=$(normalize "$key")
  [[ $combo == *+* ]] || fail "'$key' has no modifier; use something like SUPER + A"

  conflict=""
  if is_taken "$combo"; then
    conflict=$(describe_conflict "$combo")
    conflict="${conflict:-an existing binding}"
    echo "$key is already bound to: $conflict"
    if interactive; then
      if command -v gum >/dev/null; then
        gum confirm "Take it over?" || fail "aborted"
      else
        read -rp "Take it over? [y/N] " answer
        [[ $answer == [yY]* ]] || fail "aborted"
      fi
    fi
  fi

  write_binding "$key" "$conflict"
  echo "Bound $key to $NAME in $BINDINGS"
  [[ -z $conflict ]] || echo "It was previously: $conflict"
fi

omarchy plugin enable "$ID"
