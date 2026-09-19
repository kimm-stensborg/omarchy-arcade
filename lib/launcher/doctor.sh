# shellcheck shell=bash
# arcade-launcher: what is missing, and showing it.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Diagnostics
#
# The launcher is normally started from a keybinding, with no terminal to print
# to. So instead of failing silently it collects everything that is missing and
# shows it back to you: in the menu when there is a menu program, in a terminal
# window when there is not.
# --------------------------------------------------------------------------

# Each problem is a tab-separated record:
#   code <TAB> what is wrong <TAB> how to fix it <TAB> action label <TAB> action
# where action is "term <command>" (run it in a terminal window), "run <command>"
# (run it directly), or empty when there is nothing to offer.
problems=()

add_problem() {
  problems+=("$1"$'\t'"$2"$'\t'"$3"$'\t'"${4-}"$'\t'"${5-}")
}

package_command() {
  if command -v omarchy >/dev/null 2>&1; then
    printf 'omarchy pkg add'
  else
    printf 'sudo pacman -S --needed'
  fi
}

diagnose() {
  problems=()
  local pkg
  pkg="$(package_command)"

  if ! command -v "$RETROARCH_BIN" >/dev/null 2>&1; then
    add_problem "$EX_NO_RETROARCH" \
      "RetroArch is not installed" \
      "$pkg retroarch" \
      "Install RetroArch" \
      "term $pkg retroarch"
  fi

  if [[ -z "$CORE_PATH" ]]; then
    add_problem "$EX_NO_CORE" \
      "No arcade libretro core found" \
      "$pkg libretro-fbneo-git    # or libretro-mame" \
      "Install the FBNeo core" \
      "term $pkg libretro-fbneo-git"
  elif [[ ! -f "$CORE_PATH" ]]; then
    add_problem "$EX_NO_CORE" \
      "CORE_PATH points at a file that does not exist: $CORE_PATH" \
      "fix or remove CORE_PATH in $CONFIG_FILE" \
      "Edit arcade.conf" \
      "term \${EDITOR:-nano} $CONFIG_FILE"
  fi

  if [[ ! -d "$ROM_DIR" ]]; then
    add_problem "$EX_NO_ROM_DIR" \
      "ROM directory does not exist: $ROM_DIR" \
      "mkdir -p $ROM_DIR, or set ROM_DIR in $CONFIG_FILE" \
      "Create $ROM_DIR" \
      "run mkdir -p $ROM_DIR"
  elif [[ -z "$(find_roms | head -n1)" ]]; then
    add_problem "$EX_NO_ROMS" \
      "No ROMs found in $ROM_DIR" \
      "copy your .zip romsets there, or point ROM_DIR at them in $CONFIG_FILE" \
      "Open $ROM_DIR" \
      "run xdg-open $ROM_DIR"
  fi

  if [[ -z "$MENU_CMD" ]]; then
    add_problem "$EX_NO_MENU" \
      "No menu program found (wofi, rofi or fuzzel)" \
      "$pkg wofi" \
      "Install wofi" \
      "term $pkg wofi"
  fi

  ((${#problems[@]} == 0))
}

# --------------------------------------------------------------------------
# Showing the diagnosis
# --------------------------------------------------------------------------

open_terminal() {
  local command="$1" script
  printf -v script '%s\nstatus=$?\nprintf "\n"\nread -rp "Press Enter to close... "\nexit $status' "$command"

  local -a term
  if command -v xdg-terminal-exec >/dev/null 2>&1; then
    term=(xdg-terminal-exec --title="Arcade launcher" -e bash -c "$script")
  else
    local name
    for name in foot alacritty kitty ghostty xterm; do
      if command -v "$name" >/dev/null 2>&1; then
        term=("$name" -e bash -c "$script")
        break
      fi
    done
  fi

  [[ ${#term[@]} -gt 0 ]] || return 1
  setsid --fork "${term[@]}" >/dev/null 2>&1 </dev/null
}

run_action() {
  local action="$1"
  case "$action" in
    term\ *) open_terminal "${action#term }" || log "could not open a terminal for: ${action#term }" ;;
    run\ *) setsid --fork ${action#run } >>"$LOG_FILE" 2>&1 </dev/null || true ;;
    *) return 0 ;;
  esac
}

report_text() {
  printf 'Arcade launcher %s\n\n' "$VERSION"

  if ((${#problems[@]} == 0)); then
    printf 'Everything checks out - press your arcade key or run "%s".\n\n' "$PROGRAM"
  else
    local plural="things need"
    ((${#problems[@]} == 1)) && plural="thing needs"
    printf '%s %s attention before a game can start:\n\n' "${#problems[@]}" "$plural"
    local record index=0
    for record in "${problems[@]}"; do
      index=$((index + 1))
      IFS=$'\t' read -r _ what fix _ _ <<<"$record"
      printf '  %d. %s\n     fix: %s\n\n' "$index" "$what" "$fix"
    done
  fi

  printf 'Current configuration:\n\n'
  show_config | sed 's/^/  /'
  printf '\nConfig file: %s\nLog file:    %s\n' "$CONFIG_FILE" "$LOG_FILE"
}

# Present the problems through the best surface available: the menu if there is
# one (the entries starting with an arrow are actionable), otherwise a terminal
# window, otherwise just stderr and a notification.
show_problems() {
  local summary
  summary="$(printf '%s' "${problems[0]}" | cut -f2)"
  notify critical "$summary"

  local record what label action

  for record in "${problems[@]}"; do
    IFS=$'\t' read -r _ what _ _ _ <<<"$record"
    log "$what"
  done

  if [[ -n "$MENU_CMD" ]]; then
    local -a lines=() actions=()
    for record in "${problems[@]}"; do
      IFS=$'\t' read -r _ what _ label action <<<"$record"
      lines+=("⚠  $what")
      actions+=("")
      if [[ -n "$label" ]]; then
        lines+=("→  $label")
        actions+=("$action")
      fi
    done
    lines+=("ℹ  Show full details in a terminal")
    actions+=("term \"$SELF\" --doctor")

    local choice index=0
    choice="$(printf '%s\n' "${lines[@]}" | eval "$MENU_CMD" || true)"
    [[ -n "$choice" ]] || return 0

    for index in "${!lines[@]}"; do
      if [[ "${lines[$index]}" == "$choice" ]]; then
        run_action "${actions[$index]}"
        return 0
      fi
    done
    return 0
  fi

  open_terminal "\"$SELF\" --doctor" ||
    notify critical "$summary - run '$PROGRAM --doctor' in a terminal for details"
}

# Some entry points do not care about every problem: a direct launch by name
# needs no menu program, for instance.
drop_problem() {
  local code="$1" record kept=()
  for record in "${problems[@]}"; do
    [[ "${record%%$'\t'*}" == "$code" ]] || kept+=("$record")
  done
  problems=(${kept+"${kept[@]}"})
}

first_problem_code() {
  printf '%s' "${problems[0]}" | cut -f1
}
