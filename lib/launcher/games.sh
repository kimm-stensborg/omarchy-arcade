# shellcheck shell=bash
# arcade-launcher: one game's own settings.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Per-game settings
#
# The panel's game editor reads and writes these through --game and
# --game-set, the same way the arcade-wide editor uses --settings and --set:
# the launcher owns the files, the panel only asks.
# --------------------------------------------------------------------------

# "bublbobl", "bublbobl.zip" or a path to it, as the bare ROM name.
game_rom() {
  local name="${1##*/}"
  name="${name%.*}"
  [[ -n "$name" && "$name" != *[[:space:]]* && "$name" != .* ]] || die "$EX_USAGE" "not a ROM name: $1"
  printf '%s\n' "$name"
}

game_file() { printf '%s/%s.cfg\n' "$GAMES_DIR" "$1"; }

# Made on first write. It carries config_save_on_exit too: an appended file's
# values are part of what RetroArch saves, and a game's shader or binds must
# never end up in your everyday retroarch.cfg.
ensure_game_file() {
  local file
  file="$(game_file "$1")"
  if [[ ! -e "$file" ]]; then
    mkdir -p "$GAMES_DIR" || die "$EX_NO_CONFIG_DIR" "cannot create $GAMES_DIR"
    printf '%s\n' \
      "# Arcade settings for $1, loaded by RetroArch after the arcade binds." \
      "# Written by arcade-launcher and the Arcade panel; edit freely." \
      'config_save_on_exit = "false"' >"$file" || die "$EX_NO_CONFIG_DIR" "cannot write $file"
  fi
  printf '%s\n' "$file"
}

# RetroArch's desktop menu (the Qt companion window) is built at start-up,
# hidden, whenever desktop_menu_enable is on, and building it crashes now and
# then: a settings page in its Options dialog reads through a bad pointer
# (RetroArch 1.22, seen on the Input and Achievements pages). The arcade never
# shows that window, so it is not built. config_save_on_exit keeps this out of
# your everyday retroarch.cfg, where the desktop menu stays as you set it.
arcade_base_lines() {
  printf '%s\n' \
    '# Written by arcade-launcher at each launch; loaded under every arcade game.' \
    'config_save_on_exit = "false"' \
    'desktop_menu_enable = "false"' \
    'network_cmd_enable = "true"' \
    'pause_nonactive = "true"' \
    "network_cmd_port = \"$RA_PORT\""
}

arcade_base_config() {
  mkdir -p "${BASE_FILE%/*}" 2>/dev/null
  arcade_base_lines >"$BASE_FILE" 2>/dev/null && printf '%s\n' "$BASE_FILE"
}

shader_dir() {
  local dir
  dir="$(cfg_get "$(base_config)" video_shader_dir 2>/dev/null)" || dir=""
  [[ -n "$dir" && -d "$dir" ]] || dir="/usr/share/libretro/shaders/shaders_slang"
  printf '%s\n' "$dir"
}

# A game setting's value as the panel names it, from what is in the file.
game_value() {
  local file="$1" key="$2" v
  case "$key" in
    ART) cfg_get "$file" arcade_art 2>/dev/null || true ;;
    SHADER) cfg_get "$file" arcade_shader 2>/dev/null || true ;;
    SMOOTH)
      v="$(cfg_get "$file" video_smooth 2>/dev/null)" || return 0
      [[ "$v" == true ]] && echo smooth || echo sharp ;;
    INTEGER)
      v="$(cfg_get "$file" video_scale_integer 2>/dev/null)" || return 0
      [[ "$v" == true ]] && echo on || echo off ;;
    ROTATE)
      v="$(cfg_get "$file" video_rotation 2>/dev/null)" || return 0
      case "$v" in 0) echo 0 ;; 1) echo 90 ;; 2) echo 180 ;; 3) echo 270 ;; esac ;;
    CONTINUE)
      v="$(cfg_get "$file" savestate_auto_save 2>/dev/null)" || return 0
      [[ "$v" == true ]] && echo on || echo off ;;
    ASPECT)
      v="$(cfg_get "$file" aspect_ratio_index 2>/dev/null)" || return 0
      case "$v" in 22) echo core ;; 0) echo 4:3 ;; 24) echo full ;; 21) echo square ;; *) echo "index $v" ;; esac ;;
  esac
}

# "KEY<TAB>value<TAB>source" for one game: its title, then its artwork and
# picture settings ("game" when this game sets it, "default" when RetroArch
# decides), then "BIND<TAB>id<TAB>key<TAB>source" for each control, where
# the source is "game" or "shared" (the arcade binds everyone gets).
show_game() {
  local rom file key own db entry id value shared rel
  rom="$(game_rom "$1")"
  file="$(game_file "$rom")"
  printf 'GAME\t%s\t%s\n' "$rom" "$([[ -e "$file" ]] && echo present || echo absent)"
  printf 'GAME_FILE\t%s\n' "$file"

  own="$(title_lines "$TITLES_FILE" | awk -F'\t' -v r="$rom" '$1 == r { print $2; exit }')"
  db="$([[ -r "$CACHE_FILE" ]] && awk -F'\t' -v r="$rom" '$1 == r { print $2; exit }' "$CACHE_FILE")"
  if [[ -n "$own" ]]; then printf 'TITLE\t%s\tgame\n' "$own"
  else printf 'TITLE\t%s\tdefault\n' "${db:-$rom}"
  fi

  for key in ART SHADER SMOOTH ASPECT INTEGER ROTATE CONTINUE; do
    value="$(game_value "$file" "$key")"
    printf '%s\t%s\t%s\n' "$key" "$value" "$([[ -n "$value" ]] && echo game || echo default)"
  done

  local -a offered=(none)
  local dir
  dir="$(shader_dir)"
  for rel in "${SHADER_PICKS[@]}"; do [[ -f "$dir/$rel" ]] && offered+=("$rel"); done
  (IFS=$'\t'; printf 'OPTIONS_SHADER\t%s\n' "${offered[*]}")

  for entry in "${CONTROLS[@]}"; do
    id="${entry%%|*}"
    key="${entry#*|}"
    if value="$(cfg_get "$file" "$key" 2>/dev/null)"; then
      printf 'BIND\t%s\t%s\tgame\n' "$id" "$value"
    else
      shared="$(control_value "$(controls_file)" "$id")"
      printf 'BIND\t%s\t%s\tshared\n' "$id" "$shared"
    fi
  done
}

# Artwork changed kind: the cached picture goes, and with it the note that
# there was none, so the next look fetches the kind now asked for.
forget_art() {
  rm -f -- "$ART_DIR/$1.png" "$ART_DIR/$1.miss" 2>/dev/null || true
}

set_game_title() {
  local rom="$1" title="$2" tmp
  [[ "$title" != *$'\t'* ]] || die "$EX_USAGE" "a title cannot hold a tab"
  mkdir -p "${TITLES_FILE%/*}" || die "$EX_NO_CONFIG_DIR" "cannot create ${TITLES_FILE%/*}"
  [[ -e "$TITLES_FILE" ]] || : >"$TITLES_FILE" || die "$EX_NO_CONFIG_DIR" "cannot write $TITLES_FILE"
  tmp="$(mktemp "$TITLES_FILE.XXXXXX")" || die "$EX_NO_CONFIG_DIR" "cannot write $TITLES_FILE"
  ARCADE_TITLE="$title" awk -F'\t' -v r="$rom" '
    BEGIN { t = ENVIRON["ARCADE_TITLE"] }
    $1 == r { if (!done && t != "") print r "\t" t; done = 1; next }
    { print }
    END { if (!done && t != "") print r "\t" t }
  ' "$TITLES_FILE" >"$tmp" && mv -f "$tmp" "$TITLES_FILE" || { rm -f "$tmp"; die "$EX_NO_CONFIG_DIR" "cannot write $TITLES_FILE"; }
}

# One KEY=VALUE for one game; an empty value hands it back to the arcade-wide
# setting (or RetroArch's).
set_game() {
  local rom="$1" key="$2" value="$3" file ckey
  if [[ "$key" == TITLE ]]; then set_game_title "$rom" "$value"; return; fi
  file="$(ensure_game_file "$rom")"
  put() { if [[ -n "$2" ]]; then cfg_write "$file" "$1" "$2"; else cfg_clear "$file" "$1"; fi; }
  case "$key" in
    ART)
      case "$value" in ""|titles|snaps|boxarts|marquees|flyers|custom) ;;
        *) die "$EX_USAGE" "ART is titles, snaps, boxarts, marquees, flyers or custom" ;; esac
      # A picture of your own is only replaced by choosing another kind.
      [[ "$value" == custom ]] || forget_art "$rom"
      put arcade_art "$value" ;;
    SHADER)
      if [[ -z "$value" ]]; then put arcade_shader ""; put video_shader_enable ""
      elif [[ "$value" == none ]]; then put arcade_shader none; put video_shader_enable false
      else
        [[ "$value" != /* && "$value" != *..* && -f "$(shader_dir)/$value" ]] ||
          die "$EX_USAGE" "no such shader preset in $(shader_dir): $value"
        put arcade_shader "$value"; put video_shader_enable true
      fi ;;
    CONTINUE)
      # RetroArch saves the game's state as it closes and picks it up again
      # at the next start.
      case "$value" in
        "") put savestate_auto_save ""; put savestate_auto_load "" ;;
        on) put savestate_auto_save true; put savestate_auto_load true ;;
        off) put savestate_auto_save false; put savestate_auto_load false ;;
        *) die "$EX_USAGE" "CONTINUE is on or off" ;;
      esac ;;
    SMOOTH)
      case "$value" in "") put video_smooth "" ;; smooth) put video_smooth true ;; sharp) put video_smooth false ;;
        *) die "$EX_USAGE" "SMOOTH is smooth or sharp" ;; esac ;;
    INTEGER)
      case "$value" in "") put video_scale_integer "" ;; on) put video_scale_integer true ;; off) put video_scale_integer false ;;
        *) die "$EX_USAGE" "INTEGER is on or off" ;; esac ;;
    ROTATE)
      case "$value" in "") put video_rotation "" ;; 0) put video_rotation 0 ;; 90) put video_rotation 1 ;;
        180) put video_rotation 2 ;; 270) put video_rotation 3 ;; *) die "$EX_USAGE" "ROTATE is 0, 90, 180 or 270" ;; esac ;;
    ASPECT)
      local index
      case "$value" in "") index="" ;; core) index=22 ;; 4:3) index=0 ;; full) index=24 ;; square) index=21 ;;
        *) die "$EX_USAGE" "ASPECT is core, 4:3, full or square" ;; esac
      put aspect_ratio_index "$index"
      # RetroArch's "auto" would pick the core's shape over the one chosen.
      put video_aspect_ratio_auto "$([[ -n "$index" ]] && echo false)" ;;
    *)
      ckey="$(control_key "$key")" || die "$EX_USAGE" "not a game setting: $key"
      put "$ckey" "$value" ;;
  esac
}

# A picture of your own for a game's tile: copied over the cached one, and
# the game marked so it is never fetched over again.
set_game_image() {
  local rom="$1" image="$2" magic tmp
  [[ -f "$image" && -r "$image" ]] || die "$EX_USAGE" "no such file: $image"
  magic="$(head -c 8 -- "$image" | od -An -tx1 | tr -d ' \n')"
  case "$magic" in
    89504e470d0a1a0a | ffd8ff*) ;;
    *) die "$EX_USAGE" "not a PNG or JPEG image: $image" ;;
  esac
  mkdir -p "$ART_DIR" || die "$EX_NO_CONFIG_DIR" "cannot create $ART_DIR"
  tmp="$(mktemp "$ART_DIR/$rom.XXXXXX")" || die "$EX_NO_CONFIG_DIR" "cannot write $ART_DIR"
  cp -- "$image" "$tmp" && mv -f "$tmp" "$ART_DIR/$rom.png" || { rm -f "$tmp"; die "$EX_NO_CONFIG_DIR" "cannot write $ART_DIR/$rom.png"; }
  rm -f -- "$ART_DIR/$rom.miss"
  cfg_write "$(ensure_game_file "$rom")" arcade_art custom
}
