#!/bin/bash

# Remove Arcade's shortcut block and the terminal symlinks.
#
#   ./uninstall.sh            remove the binding block and the symlinks
#   ./uninstall.sh --purge    also remove your config, titles and cache
#
# The plugin itself is removed the way every plugin is:
#
#   omarchy plugin remove io.github.kimm-stensborg.arcade

set -euo pipefail

ID="io.github.kimm-stensborg.arcade"
BINDINGS="$HOME/.config/hypr/bindings.lua"
MARKER="-- Arcade overlay ($ID)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/omarchy"
BIN_DIR="$HOME/.local/bin"

PURGE=0
[[ "${1-}" == "--purge" ]] && PURGE=1

note() { printf '  %s\n' "$*"; }

for script in arcade-launcher arcade-rdb-dump arcade-artwork; do
  if [[ -L "$BIN_DIR/$script" || -e "$BIN_DIR/$script" ]]; then
    rm -f "$BIN_DIR/$script"
    note "removed $BIN_DIR/$script"
  fi
done

if [[ -f $BINDINGS ]] && grep -qF "$MARKER" "$BINDINGS"; then
  cp "$BINDINGS" "$BINDINGS.bak.$(date +%s)"
  tmp=$(mktemp)
  # The block runs from the marker to the next blank line; the blank line above
  # it goes too, so removing and re-adding cannot grow the file.
  awk -v marker="$MARKER" '
    !skip && NF == 0 { held = held $0 "\n"; next }
    $0 == marker { skip = 1; held = ""; next }
    skip && NF == 0 { skip = 0; next }
    skip { next }
    { printf "%s", held; held = ""; print }
    END { printf "%s", held }
  ' "$BINDINGS" >"$tmp"
  mv "$tmp" "$BINDINGS"
  note "removed the shortcut block from $BINDINGS (backup kept)"
  command -v hyprctl >/dev/null && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] &&
    hyprctl reload >/dev/null && note "reloaded Hyprland"
fi

if ((PURGE)); then
  for file in "$CONFIG_DIR/arcade.conf" "$CONFIG_DIR/arcade-titles.tsv" \
    "$CACHE_DIR/arcade-titles.cache.tsv" "$CACHE_DIR/arcade.log"; do
    [[ -e $file ]] && { rm -f "$file"; note "removed $file"; }
  done
  if [[ -d "$CACHE_DIR/arcade-art" ]]; then
    rm -rf "$CACHE_DIR/arcade-art"
    note "removed $CACHE_DIR/arcade-art"
  fi
else
  note "kept $CONFIG_DIR/arcade.conf and arcade-titles.tsv (--purge removes them)"
fi

echo
echo "Remove the plugin itself with:"
echo "  omarchy plugin remove $ID"
