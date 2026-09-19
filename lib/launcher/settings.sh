# shellcheck shell=bash
# arcade-launcher: arcade.conf, as the overlay's editor reads and writes it.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Settings (the overlay's editor talks to these two)
# --------------------------------------------------------------------------

# Whether the config file assigns a key itself, as opposed to the value coming
# from the environment or from a default. Only plain "KEY=" lines count, which
# is all conf_set ever writes.
conf_declares() {
  [[ -r "$CONFIG_FILE" ]] || return 1
  grep -qE "^[[:space:]]*$1=" "$CONFIG_FILE"
}

setting_source() {
  local key="$1"
  if conf_declares "$key"; then printf 'file\n'
  elif [[ "$ENV_KEYS" == *" $key "* ]]; then printf 'env\n'
  elif [[ "$key" == CORE_PATH || "$key" == MENU_CMD ]]; then printf 'auto\n'
  else printf 'default\n'
  fi
}

# Whether a setting points at something that is not there. --doctor diagnoses
# this properly; this is the editor's early warning, so a mistyped directory is
# visible in the row that made it rather than as a library that lists nothing.
setting_state() {
  local key="$1" value="$2"
  [[ -n "$value" ]] || { printf 'ok\n'; return 0; }
  case "$key" in
    ROM_DIR) [[ -d "$value" ]] || { printf 'missing\n'; return 0; } ;;
    CORE_PATH | RETROARCH_CONFIG)
      [[ -f "$value" ]] || { printf 'missing\n'; return 0; } ;;
  esac
  printf 'ok\n'
}

# "KEY<TAB>value<TAB>source<TAB>state" per setting: what the panel reads to draw
# its editor, what tells it which rows are the user's own choices, and which of
# them point at nothing.
#
# "OPTIONS_<KEY><TAB>one<TAB>two" lines carry what a row can be arrowed through
# where the answer is a list of what is installed rather than free text.
show_settings() {
  local key
  printf 'CONFIG_FILE\t%s\t%s\n' "$CONFIG_FILE" "$([[ -r "$CONFIG_FILE" ]] && echo present || echo absent)"
  for key in "${SETTING_KEYS[@]}"; do
    printf '%s\t%s\t%s\t%s\n' "$key" "${!key-}" "$(setting_source "$key")" \
      "$(setting_state "$key" "${!key-}")"
  done

  local -a options
  mapfile -t options < <(arcade_core_paths)
  if ((${#options[@]})); then
    printf 'OPTIONS_CORE_PATH'
    printf '\t%s' "${options[@]}"
    printf '\n'
  fi

  mapfile -t options < <(menu_presets)
  if ((${#options[@]})); then
    printf 'OPTIONS_MENU_CMD'
    printf '\t%s' "${options[@]}"
    printf '\n'
  fi
}

# Values are written double-quoted so "$HOME/Games/roms" keeps expanding the
# way the shipped example does. Backslashes, quotes and command substitution
# are escaped: the file is sourced, and a directory name is not a program.
conf_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\`/\\\`}"
  value="${value//\$(/\\\$(}"
  printf '"%s"' "$value"
}

# Set one key, or remove its line when the value is empty, so the default takes
# over again. An existing assignment is replaced where it stands, and a new one
# lands under the commented example for that key when the file has one, which
# keeps a config that started from arcade.conf.example readable -- and leaves
# the explanation behind when the setting is reset away again.
conf_set() {
  local key="$1" value="$2" repl="" remove=0 dir tmp shown
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]] || die "$EX_USAGE" "not a setting name: $key"
  [[ -n "$value" ]] || remove=1
  ((remove)) || repl="$key=$(conf_quote "$value")"

  dir="${CONFIG_FILE%/*}"
  shown="${CONFIG_FILE/#$HOME\//\~/}"
  mkdir -p "$dir" || die "$EX_NO_CONFIG_DIR" "cannot create $dir"
  if [[ ! -e "$CONFIG_FILE" ]]; then
    if ((remove)); then return 0; fi
    printf '%s\n' \
      "# $shown" \
      "#" \
      "# Configuration for arcade-launcher and the Arcade overlay. Plain shell:" \
      "# VAR=value, # for comments. Edit it here or in the panel's settings." \
      "" >"$CONFIG_FILE"
  fi

  # The new line travels in the environment rather than through -v: awk expands
  # escape sequences in a -v assignment, which would undo exactly the escaping
  # conf_quote just did and put a live backtick back into a sourced file.
  tmp="$(mktemp "$CONFIG_FILE.XXXXXX")"
  ARCADE_REPL="$repl" awk -v key="$key" -v remove="$remove" '
    BEGIN { repl = ENVIRON["ARCADE_REPL"] }
    $0 ~ "^[ \t]*" key "=" {
      if (!done && remove != 1) { print repl; done = 1 }
      next
    }
    # A commented example line: keep it and write the setting under it, so the
    # file a person started from still explains itself after an edit.
    !done && remove != 1 && $0 ~ "^[ \t]*#[ \t]*" key "=" { print; print repl; done = 1; next }
    { print }
    END { if (!done && remove != 1) print repl }
  ' "$CONFIG_FILE" >"$tmp" && mv "$tmp" "$CONFIG_FILE" || {
    rm -f "$tmp"
    die "$EX_NO_CONFIG_DIR" "cannot write $CONFIG_FILE"
  }
}
