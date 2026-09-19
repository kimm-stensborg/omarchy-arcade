# shellcheck shell=bash
# arcade-launcher: the arcade binds, in their own RetroArch config.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Controls
#
# RetroArch's own binds put "insert coin" on right shift, which is nobody's
# idea of an arcade cabinet. These read and write a small file of arcade binds
# that RetroArch loads on top of its own config with --appendconfig, so the
# binds that make a cabinet a cabinet change without touching the RetroArch
# you use for everything else -- and everything else in that RetroArch (the
# shader, the video driver, the paths) carries on applying to the arcade too.
# --------------------------------------------------------------------------

readonly CONTROLS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/arcade-retroarch.cfg"
readonly RETROARCH_MAIN_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/retroarch/retroarch.cfg"
# What every arcade game is started with, under the arcade binds and the
# game's own settings. Written fresh at each launch, so it holds whatever this
# version of the launcher needs; see arcade_base_config.
readonly BASE_FILE="${XDG_RUNTIME_DIR:-/tmp}/omarchy-arcade-base.cfg"
# One RetroArch config per game, "<rom>.cfg", loaded after the shared controls
# so what is set there wins for that game only: picture settings, the
# controls it needs changed, and the panel's own keys (arcade_*), which
# RetroArch reads past.
readonly GAMES_DIR="${ARCADE_GAMES_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/arcade-games}"
# Shaders the game editor offers, relative to RetroArch's shader directory,
# when they are installed there: a handful of well-known looks rather than
# the hundreds in the pack.
readonly SHADER_PICKS=(
  crt/crt-royale.slangp crt/crt-guest-advanced.slangp crt/crt-geom.slangp crt/crt-lottes.slangp
  crt/crt-easymode.slangp crt/crt-pi.slangp crt/zfast-crt.slangp crt/mame_hlsl.slangp
  scanlines/scanline.slangp
)

controls_file() { printf '%s\n' "$CONTROLS_FILE"; }

# The config the binds are layered over: the arcade-only one RETROARCH_CONFIG
# names, when there is one, otherwise the RetroArch config itself.
base_config() {
  if [[ -n "$RETROARCH_CONFIG" ]]; then printf '%s\n' "$RETROARCH_CONFIG"
  else printf '%s\n' "$RETROARCH_MAIN_CONFIG"
  fi
}

control_key() {
  local entry
  for entry in "${CONTROLS[@]}"; do
    [[ "${entry%%|*}" == "$1" ]] && { printf '%s\n' "${entry#*|}"; return 0; }
  done
  return 1
}

# One "key = "value"" line out of a retroarch.cfg.
cfg_get() {
  local file="$1" key="$2" line
  [[ -r "$file" ]] || return 1
  line="$(grep -m1 -E "^[[:space:]]*$key[[:space:]]*=" "$file")" || return 1
  line="${line#*=}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  line="${line%\"}"
  line="${line#\"}"
  printf '%s\n' "$line"
}

# The binds file, made if it is not there yet: nothing but the binds and one
# setting that keeps them in it.
#
# RetroArch saves its config on exit, and an appended file's values are part
# of what it saves -- so without this, one arcade session would write the
# arcade binds into your everyday retroarch.cfg. Appended settings win, so
# saying "false" here stops that save for arcade sessions only.
ensure_controls_file() {
  local file
  file="$(controls_file)"
  if [[ ! -e "$file" ]]; then
    mkdir -p "${file%/*}" || die "$EX_NO_CONFIG_DIR" "cannot create ${file%/*}"
    printf '%s\n' \
      "# Arcade binds, loaded by RetroArch on top of its own config (--appendconfig)." \
      "# Written by arcade-launcher and the Arcade panel; edit freely." >"$file" ||
      die "$EX_NO_CONFIG_DIR" "cannot write $file"
  fi
  guard_controls_file "$file"
  printf '%s\n' "$file"
}

guard_controls_file() {
  [[ "$(cfg_get "$1" config_save_on_exit 2>/dev/null)" == "false" ]] || cfg_write "$1" config_save_on_exit "false"
}

# Up to 1.2.0 the buttons were numbered for fighting games -- Button 1 on Y --
# so the MAME layout put Ctrl where most games have their Button 3. A binds
# file holding exactly that old layout is rewritten to the corrected one.
migrate_button_numbering() {
  local file="$CONTROLS_FILE" key want
  [[ -f "$file" ]] || return 0
  for want in "y|ctrl" "x|alt" "l|space" "b|shift" "a|z" "r|x"; do
    key="input_player1_${want%%|*}"
    [[ "$(cfg_get "$file" "$key" 2>/dev/null)" == "${want#*|}" ]] || return 0
  done
  apply_preset mame
}

# 1.1.0 kept the binds in a full copy of retroarch.cfg and pointed
# RETROARCH_CONFIG at it, so a shader or driver changed in RetroArch later
# never reached the arcade. Such a copy is cut down to the binds, the rest kept
# beside it as .bak, and RETROARCH_CONFIG handed back -- but only when it names
# the file this launcher made, never one chosen by hand.
migrate_controls() {
  [[ -n "$RETROARCH_CONFIG" && "$RETROARCH_CONFIG" == "$CONTROLS_FILE" ]] || return 0
  conf_declares RETROARCH_CONFIG || return 0

  local file="$CONTROLS_FILE" keys="config_save_on_exit" entry tmp
  if [[ -f "$file" ]]; then
    for entry in "${CONTROLS[@]}"; do keys+=" ${entry#*|}"; done
    [[ -e "$file.bak" ]] || cp -p -- "$file" "$file.bak" 2>/dev/null || return 0
    tmp="$(mktemp "$file.XXXXXX")" || return 0
    awk -v keys="$keys" '
      BEGIN { n = split(keys, k, " "); for (i = 1; i <= n; i++) keep[k[i]] = 1 }
      { key = $0; sub(/[ \t]*=.*/, "", key); sub(/^[ \t]*/, "", key) }
      key in keep { print }
    ' "$file" >"$tmp" && mv -f "$tmp" "$file" || { rm -f "$tmp"; return 0; }
  fi
  conf_set RETROARCH_CONFIG ""
  RETROARCH_CONFIG=""
  printf '\n=== %s moved the arcade binds out of a full retroarch.cfg copy (kept as %s) ===\n' \
    "$(date -Is)" "$file.bak" >>"$LOG_FILE" 2>/dev/null || true
}

cfg_write() {
  local file="$1" key="$2" value="$3" tmp
  tmp="$(mktemp "$file.XXXXXX")"
  ARCADE_REPL="$key = \"$value\"" awk -v key="$key" '
    BEGIN { repl = ENVIRON["ARCADE_REPL"] }
    $0 ~ "^[ \t]*" key "[ \t]*=" { if (!done) { print repl; done = 1 } next }
    { print }
    END { if (!done) print repl }
  ' "$file" >"$tmp" && mv "$tmp" "$file" || {
    rm -f "$tmp"
    die "$EX_NO_CONFIG_DIR" "cannot write $file"
  }
}

# Remove a bind from the profile so whatever RetroArch's own config says takes
# over again -- the same shape of reset as removing a line from arcade.conf.
cfg_clear() {
  local file="$1" key="$2" tmp
  [[ -e "$file" ]] || return 0
  tmp="$(mktemp "$file.XXXXXX")"
  awk -v key="$key" '$0 ~ "^[ \t]*" key "[ \t]*=" { next } { print }' "$file" >"$tmp" &&
    mv "$tmp" "$file" || { rm -f "$tmp"; die "$EX_NO_CONFIG_DIR" "cannot write $file"; }
}

# Which preset the profile currently matches, so the panel can say "MAME
# standard" rather than making someone read seventeen binds and decide.
# The "id|key" entries of a named layout, or nothing if there is no such one.
preset_entries() {
  case "$1" in
    mame) printf '%s\n' "${PRESET_MAME[@]}" ;;
    retroarch) printf '%s\n' "${PRESET_RETROARCH[@]}" ;;
    *) return 1 ;;
  esac
}

controls_preset() {
  local name entry id want got file matches
  file="$(controls_file)"
  for name in mame retroarch; do
    matches=1
    while IFS= read -r entry; do
      id="${entry%%|*}"
      want="${entry#*|}"
      got="$(control_value "$file" "$id")"
      [[ "$got" == "$want" ]] || { matches=0; break; }
    done < <(preset_entries "$name")
    ((matches)) && { printf '%s\n' "$name"; return 0; }
  done
  printf 'custom\n'
}

# What a control is bound to right now: the arcade binds first, then the
# RetroArch config they are layered over, then RetroArch's own default -- which is
# the RetroArch layout, so a setup nobody has touched reads as that layout
# rather than as a column of blanks.
control_value() {
  local file="$1" id="$2" key value entry
  key="$(control_key "$id")" || return 0
  value="$(cfg_get "$file" "$key" 2>/dev/null)" && { printf '%s\n' "$value"; return 0; }
  value="$(cfg_get "$(base_config)" "$key" 2>/dev/null)" && { printf '%s\n' "$value"; return 0; }
  for entry in "${PRESET_RETROARCH[@]}"; do
    [[ "${entry%%|*}" == "$id" ]] && { printf '%s\n' "${entry#*|}"; return 0; }
  done
  printf '\n'
}

control_source() {
  local file="$1" id="$2" key
  key="$(control_key "$id")" || return 0
  if [[ -r "$file" ]] && grep -qE "^[[:space:]]*$key[[:space:]]*=" "$file"; then printf 'file\n'
  elif [[ -r "$(base_config)" ]] && grep -qE "^[[:space:]]*$key[[:space:]]*=" "$(base_config)"; then printf 'retroarch\n'
  else printf 'default\n'
  fi
}

# "id<TAB>key<TAB>source" per control, with the profile and the preset it
# matches on the first two lines. The panel's controls editor reads this.
show_controls() {
  local file entry id
  file="$(controls_file)"
  printf 'CONTROLS_FILE\t%s\t%s\n' "$file" "$([[ -e "$file" ]] && echo present || echo absent)"
  printf 'PRESET\t%s\t%s\n' "$(controls_preset)" "ok"
  for entry in "${CONTROLS[@]}"; do
    id="${entry%%|*}"
    printf '%s\t%s\t%s\n' "$id" "$(control_value "$file" "$id")" "$(control_source "$file" "$id")"
  done
}

set_control() {
  local id="$1" value="$2" key file
  key="$(control_key "$id")" || die "$EX_USAGE" "not a control: $id"
  file="$(ensure_controls_file)"
  if [[ -n "$value" ]]; then cfg_write "$file" "$key" "$value"
  else cfg_clear "$file" "$key"
  fi
}

apply_preset() {
  local name="$1" entry file
  preset_entries "$name" >/dev/null || die "$EX_USAGE" "no such control layout: $name"
  file="$(ensure_controls_file)"
  while IFS= read -r entry; do
    cfg_write "$file" "$(control_key "${entry%%|*}")" "${entry#*|}"
  done < <(preset_entries "$name")
}

ensure_cache() {
  if cache_is_stale; then
    rebuild_cache || true
  fi
}

cmd_list() {
  ensure_cache
  local lines
  lines="$(build_menu_lines "${1:-wishlist}")"
  [[ -n "$lines" ]] || die "$EX_NO_ROMS" "no ROMs found in $ROM_DIR"
  printf '%s\n' "$lines"
}

cmd_menu() {
  [[ -n "$MENU_CMD" ]] ||
    die "$EX_NO_MENU" "no menu program found; install wofi (omarchy pkg add wofi)"

  ensure_cache

  local lines choice rom
  lines="$(build_menu_lines)"
  [[ -n "$lines" ]] || die "$EX_NO_ROMS" "no ROMs found in $ROM_DIR"

  # Only the title is shown; the tab-separated path rides along for the lookup.
  choice="$(printf '%s\n' "$lines" | cut -f1 | eval "$MENU_CMD" || true)"
  [[ -n "$choice" ]] || exit 0

  rom="$(printf '%s\n' "$lines" | awk -F'\t' -v want="$choice" '!found && $1 == want { print $2; found = 1 }')"
  [[ -n "$rom" ]] || die "$EX_UNKNOWN_ROM" "no ROM matches the selection: $choice"

  launch_rom "$rom"
}

cmd_direct() {
  local wanted="$1" rom

  # The overlay passes the full path it was given by --list; a person passes
  # the short name. Both mean the same game.
  if [[ -f "$wanted" ]]; then
    launch_rom "$wanted"
    return
  fi

  rom="$(resolve_rom_name "$wanted")" ||
    die "$EX_UNKNOWN_ROM" "no ROM named '$wanted' in $ROM_DIR"
  launch_rom "$rom"
}
