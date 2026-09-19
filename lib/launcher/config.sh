# shellcheck shell=bash
# arcade-launcher: reading arcade.conf and finding RetroArch, the core and the menu.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

load_config() {
  # Which settings arrived from the environment. Sourcing the file overwrites
  # them in place, so the only chance to tell "set for this run" apart from
  # "written in the file" is before the source line.
  ENV_KEYS=" "
  local key
  for key in "${SETTING_KEYS[@]}"; do
    [[ -n "${!key+set}" ]] && ENV_KEYS+="$key "
  done

  # The config file is a plain shell fragment: VAR=value lines, comments allowed.
  if [[ -r "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
  fi

  : "${ROM_DIR:=$HOME/Games/roms}"
  : "${ROM_EXTS:=zip 7z chd}"
  : "${TITLES_FILE:=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/arcade-titles.tsv}"
  # The copy that ships with the plugin, used when no user overrides exist yet,
  # so titles are clean the first time the panel opens.
  : "${SHIPPED_TITLES_FILE:=${SELF%/bin/*}/share/arcade-titles.tsv}"
  # Genre, players and screen orientation per romset, from FinalBurn Neo's
  # driver table (tools/make-gameinfo.py).
  : "${GAMEINFO_FILE:=${SELF%/bin/*}/share/arcade-gameinfo.tsv}"
  : "${ARTWORK:=on}"
  : "${ART_KINDS:=titles snaps boxarts}"
  : "${ART_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/arcade-art}"
  # Read by the overlay only; the launcher just carries them so that one file
  # and one editor cover every arcade setting.
  : "${TILE_SIZE:=300}"
  : "${MAX_COLUMNS:=6}"
  : "${SORT_BY:=last played}"
  : "${ATTRACT_AFTER:=60}"
  : "${GROUP_VERSIONS:=on}"
  : "${CACHE_FILE:=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/arcade-titles.cache.tsv}"
  : "${LOG_FILE:=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/arcade.log}"
  : "${RETROARCH_CONFIG:=}"

  ROM_DIR="${ROM_DIR/#\~/$HOME}"
  TITLES_FILE="${TITLES_FILE/#\~/$HOME}"
  CACHE_FILE="${CACHE_FILE/#\~/$HOME}"
  LOG_FILE="${LOG_FILE/#\~/$HOME}"
  [[ -n "$RETROARCH_CONFIG" ]] && RETROARCH_CONFIG="${RETROARCH_CONFIG/#\~/$HOME}"

  [[ -n "${CORE_PATH:-}" ]] || CORE_PATH="$(detect_core)"
  CORE_PATH="${CORE_PATH/#\~/$HOME}"

  [[ -n "${MENU_CMD:-}" ]] || MENU_CMD="$(detect_menu)"
  migrate_controls
  migrate_button_numbering
}

# The arcade cores worth offering, best first: FBNeo is the better fit for
# classic arcade sets, MAME the fallback. Autodetection takes the first of
# these that is installed; the settings editor offers all of them.
readonly ARCADE_CORES=(fbneo mame mame2003_plus mame2010 mame2016)
readonly CORE_DIRS=("$HOME/.config/retroarch/cores" "/usr/lib/libretro" "/usr/local/lib/libretro")

detect_core() {
  local path
  path="$(arcade_core_paths | head -n1)"
  printf '%s\n' "$path"
  return 0
}

# Every arcade core actually installed, in the order autodetection would pick
# them. The editor turns this into a list to arrow through, so choosing a core
# is not typing an absolute path from memory.
arcade_core_paths() {
  local dir core
  for dir in "${CORE_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    for core in "${ARCADE_CORES[@]}"; do
      [[ -f "$dir/${core}_libretro.so" ]] && printf '%s\n' "$dir/${core}_libretro.so"
    done
  done
  return 0
}

detect_menu() {
  menu_presets | head -n1
  return 0
}

# A ready-made command per dmenu program that is installed, same order as
# autodetection. Only what is installed: a preset for a program that is not
# there would be a setting that cannot work.
menu_presets() {
  command -v wofi >/dev/null 2>&1 && printf '%s\n' "wofi --dmenu --insensitive --prompt Arcade"
  command -v rofi >/dev/null 2>&1 && printf '%s\n' "rofi -dmenu -i -p Arcade"
  command -v fuzzel >/dev/null 2>&1 && printf '%s\n' "fuzzel --dmenu --prompt=Arcade: "
  return 0
}
