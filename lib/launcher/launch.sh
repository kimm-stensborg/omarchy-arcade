# shellcheck shell=bash
# arcade-launcher: starting a game, watching that it starts, the play history.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Launching
# --------------------------------------------------------------------------

launch_rom() {
  local rom="$1" running pid path
  local -a cmd=("$RETROARCH_BIN" --verbose -L "$CORE_PATH")

  # One cabinet, one game. The game already running is brought back rather
  # than started twice; a different one is closed first, the way picking a new
  # game on a multi-game cabinet ends the one in progress. RetroArch quits
  # cleanly on SIGTERM, so high scores are saved on the way out.
  running="$(running_game)"
  if [[ -n "$running" ]]; then
    IFS=$'\t' read -r pid path <<<"$running"
    if [[ "$path" == "$rom" ]]; then
      # Paused while the panel sat on top of it: it picks up where it was.
      set_game_paused playing || true
      focus_window "$pid"
      record_play "$rom" "$(date +%s)"
      return 0
    fi
    stop_game "$pid"
  elif pid="$(pgrep -x -- "${RETROARCH_BIN##*/}" | head -n1)" && [[ -n "$pid" ]]; then
    # A RetroArch this launcher did not start may be halfway through anything;
    # it is not ours to close.
    focus_window "$pid"
    die "$EX_BUSY" "RetroArch is already running. Close it first to start $(rom_title "$rom")."
  fi

  [[ -n "$RETROARCH_CONFIG" ]] && cmd+=(--config "$RETROARCH_CONFIG")
  # What every arcade game gets, then the arcade binds, then this game's own
  # settings over them: RetroArch takes several appended configs as one
  # "|"-separated list, the last word winning.
  local -a append=()
  local base
  base="$(arcade_base_config)" && append+=("$base")
  if [[ -f "$CONTROLS_FILE" ]]; then
    # A hand edit may have dropped the line that keeps these binds out of
    # the everyday config; it goes back before RetroArch can save over it.
    guard_controls_file "$CONTROLS_FILE"
    append+=("$CONTROLS_FILE")
  fi
  local name game shader
  name="${rom##*/}"
  name="${name%.*}"
  game="$(game_file "$name")"
  if [[ -f "$game" ]]; then
    guard_controls_file "$game"
    append+=("$game")
    shader="$(cfg_get "$game" arcade_shader 2>/dev/null)" || shader=""
    if [[ -n "$shader" && "$shader" != none && -f "$(shader_dir)/$shader" ]]; then
      cmd+=(--set-shader "$(shader_dir)/$shader")
    fi
  fi
  ((${#append[@]})) && cmd+=(--appendconfig "$(IFS='|'; printf '%s' "${append[*]}")")
  cmd+=("$rom")

  # Omarchy launches graphical apps through uwsm so they get their own scope.
  # uwsm-app execs its way down to RetroArch, so the pid started here is the
  # game's for as long as it runs.
  if command -v uwsm-app >/dev/null 2>&1; then
    cmd=(uwsm-app -- "${cmd[@]}")
  fi

  mkdir -p "${LOG_FILE%/*}"
  trim_log
  printf '\n=== %s launching %s ===\n' "$(date -Is)" "$rom" >>"$LOG_FILE"
  local offset started
  offset="$(stat -c %s -- "$LOG_FILE")"
  started="$(date +%s)"

  # Detach fully: the keybinding process exits immediately, the game keeps
  # running. Not setsid --fork, because the pid is what everything after this
  # needs.
  setsid "${cmd[@]}" >>"$LOG_FILE" 2>&1 </dev/null &
  pid=$!
  disown "$pid" 2>/dev/null || true

  printf '%s\t%s\n' "$pid" "$rom" >"$RUNNING_FILE" 2>/dev/null || true
  record_play "$rom" "$started"

  # Watched from the side, so whatever started us -- the panel, a keybinding
  # -- is not held up while RetroArch loads.
  watch_launch "$pid" "$rom" "$offset" "$started" </dev/null >/dev/null 2>&1 &
  disown $! 2>/dev/null || true
}

# ---- talking to the game
#
# RetroArch listens on a UDP port while an arcade game runs (the arcade turns
# that on for its own games; see arcade_base_lines), so the panel can pause the
# game it is sitting on top of and let it go again.

# One command to the running game, and its answer when it has one.
ra_command() {
  python3 - "$RA_PORT" "$1" <<'EOF' 2>/dev/null
import socket, sys
port, command = int(sys.argv[1]), sys.argv[2]
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(1.0)
try:
    sock.sendto(command.encode(), ("127.0.0.1", port))
    print(sock.recvfrom(4096)[0].decode(errors="replace").strip())
except OSError:
    pass
EOF
}

# "playing", "paused", or nothing when no arcade game is running.
game_state() {
  running_game >/dev/null || return 0
  local answer
  answer="$(ra_command GET_STATUS)"
  case "$answer" in
    *PAUSED*) printf 'paused\n' ;;
    *PLAYING*) printf 'playing\n' ;;
  esac
}

# Pause the running game, or let it go again. Saying which rather than
# toggling means the panel and the game agree even if one of them was already
# in that state.
set_game_paused() {
  local want="$1" state
  state="$(game_state)"
  [[ -n "$state" ]] || return 1
  if [[ "$want" == paused && "$state" == playing ]] || [[ "$want" == playing && "$state" == paused ]]; then
    ra_command PAUSE_TOGGLE >/dev/null
  fi
  return 0
}

# "pid<TAB>path" of the game this launcher started, if it is still running.
# A pid alone is not enough -- after a reboot or a crash it may belong to
# something else entirely -- so the process has to still be a RetroArch.
running_game() {
  local pid path
  [[ -r "$RUNNING_FILE" ]] || return 0
  IFS=$'\t' read -r pid path <"$RUNNING_FILE" || true
  [[ "$pid" =~ ^[0-9]+$ ]] || return 0
  if kill -0 "$pid" 2>/dev/null && tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -q -- "${RETROARCH_BIN##*/}"; then
    printf '%s\t%s\n' "$pid" "$path"
  fi
  return 0
}

stop_game() {
  local pid="$1" tries=0
  kill -TERM "$pid" 2>/dev/null || return 0
  while kill -0 "$pid" 2>/dev/null && ((tries < 50)); do
    sleep 0.1
    tries=$((tries + 1))
  done
  kill -KILL "$pid" 2>/dev/null || true
}

focus_window() {
  command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl dispatch "hl.dsp.focus({ window = \"pid:$1\" })" >/dev/null 2>&1 || true
}

record_play() {
  local rom="$1" when="$2"
  mkdir -p "${HISTORY_FILE%/*}" 2>/dev/null || return 0
  printf '%s\t%s\n' "$when" "$rom" >>"$HISTORY_FILE" 2>/dev/null || return 0

  # Only the latest play of each game and how many there were matter, so the
  # file is folded down to that once it has grown, rather than growing for
  # as long as it is used.
  if (($(wc -l <"$HISTORY_FILE") > 1000)); then
    local tmp
    tmp="$(mktemp "$HISTORY_FILE.XXXXXX")" || return 0
    awk -F'\t' '
      NF >= 2 {
        if ($1 + 0 > last[$2] + 0) last[$2] = $1
        plays[$2] += (NF >= 3 && $3 + 0 > 0) ? $3 : 1
      }
      END { for (p in last) printf "%s\t%s\t%s\n", last[p], p, plays[p] }' \
      "$HISTORY_FILE" | sort -n >"$tmp" && mv -f "$tmp" "$HISTORY_FILE" || rm -f "$tmp"
  fi
}

# The launch headers arcade.log has always had are a history already, so the
# first listing after an upgrade starts from them rather than from nothing.
seed_history() {
  [[ -e "$HISTORY_FILE" || ! -r "$LOG_FILE" ]] && return 0
  mkdir -p "${HISTORY_FILE%/*}" 2>/dev/null || return 0
  local lines
  lines="$(sed -nE 's/^=== ([^ ]+) launching (.*) ===$/\1\t\2/p' -- "$LOG_FILE")"
  [[ -n "$lines" ]] || return 0
  paste <(cut -f1 <<<"$lines" | date -f - +%s 2>/dev/null) <(cut -f2 <<<"$lines") |
    awk -F'\t' '$1 ~ /^[0-9]+$/' >"$HISTORY_FILE" 2>/dev/null || true
}

# A launch that failed is not a game you played.
forget_play() {
  local rom="$1" when="$2" tmp
  [[ -w "$HISTORY_FILE" ]] || return 0
  tmp="$(mktemp "$HISTORY_FILE.XXXXXX")" || return 0
  awk -F'\t' -v when="$when" -v rom="$rom" '!($1 == when && $2 == rom)' "$HISTORY_FILE" >"$tmp" &&
    mv -f "$tmp" "$HISTORY_FILE" || rm -f "$tmp"
}

# Add or remove favourites by ROM name ("bublbobl", or a path to it). The file is
# rewritten whole, sorted, each name once, so editing it by hand stays easy.
set_favourites() {
  local mode="$1" tmp name
  shift
  mkdir -p "${FAVOURITES_FILE%/*}" || die 1 "cannot create ${FAVOURITES_FILE%/*}"
  local -a names=()
  for name in "$@"; do
    name="${name##*/}"
    name="${name%.*}"
    [[ -n "$name" && "$name" != *[[:space:]]* ]] || die "$EX_USAGE" "not a ROM name: $name"
    names+=("$name")
  done
  tmp="$(mktemp "$FAVOURITES_FILE.XXXXXX")" || die 1 "cannot write $FAVOURITES_FILE"
  {
    [[ -r "$FAVOURITES_FILE" ]] && cat -- "$FAVOURITES_FILE"
    if [[ "$mode" == add ]]; then printf '%s\n' "${names[@]}"; fi
  } | awk -v drop="$([[ "$mode" == remove ]] && printf '%s ' "${names[@]}")" '
    BEGIN { n = split(drop, d, " "); for (i = 1; i <= n; i++) gone[d[i]] = 1 }
    { sub(/[ \t\r]+$/, "") }
    $0 != "" && !($0 in gone) && !seen[$0]++
  ' | sort >"$tmp" && mv -f "$tmp" "$FAVOURITES_FILE" || { rm -f "$tmp"; die 1 "cannot write $FAVOURITES_FILE"; }
}

# RetroArch runs with --verbose so a failure says why, which makes the log
# grow: past 4 MB only the last megabyte is kept.
trim_log() {
  [[ -f "$LOG_FILE" ]] || return 0
  (($(stat -c %s -- "$LOG_FILE") > 4194304)) || return 0
  local tmp
  tmp="$(mktemp "$LOG_FILE.XXXXXX")" || return 0
  tail -c 1048576 -- "$LOG_FILE" >"$tmp" && mv -f "$tmp" "$LOG_FILE" || rm -f "$tmp"
}

# Read to the end rather than stopping at the first match: an awk that quits
# early kills title_sources mid-write, and under pipefail that failure would
# take the whole launcher down with it.
rom_title() {
  local rom="${1##*/}"
  rom="${rom%.*}"
  title_sources | awk -F'\t' -v rom="$rom" '
    !found && $1 == rom && NF >= 2 { title = $2; found = 1 }
    END { print (found ? title : rom) }'
}

# Whether the game actually started. A romset that is incomplete, the wrong
# version or missing its BIOS does not make RetroArch exit: FBNeo shows a
# screen of its own listing the missing files, other cores leave RetroArch in
# its menu -- from a keybinding, either looks like nothing happened. So the
# log is read until the core reports the game's picture (started) or a
# failure, and a failure closes RetroArch and says why.
watch_launch() {
  local pid="$1" rom="$2" offset="$3" started="$4" tries=0 chunk reason=""
  while ((tries < 80)); do
    # Replaced by another launch: closed on purpose, so not a failure -- and
    # what follows in the log is that game's, not this one's.
    [[ "$(cut -f1 "$RUNNING_FILE" 2>/dev/null)" == "$pid" ]] || return 0
    # This launch's part of the log only, up to the next launch's header.
    chunk="$(tail -c +"$((offset + 1))" -- "$LOG_FILE" 2>/dev/null | awk '/^=== .* launching .* ===$/ { done = 1 } !done { print }')"
    # Failure is looked for before success, because it can look like success:
    # FBNeo lists the files it lacks and then boots a screen of its own saying
    # so, which reports a picture like any game.
    if grep -qE 'is required$|Failed to load content|\[Core\] Unloading game' <<<"$chunk"; then
      reason="$(launch_failure "$chunk")"
      reason="${reason:-RetroArch could not load it.}"
      stop_game "$pid"
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      reason="$(launch_failure "$chunk")"
      reason="${reason:-RetroArch closed as soon as it started.}"
      break
    fi
    if grep -q '\[Core\] Geometry:' <<<"$chunk"; then
      record_check "$rom" ok ""
      return 0
    fi
    sleep 0.25
    tries=$((tries + 1))
  done
  # Neither answer within twenty seconds: a big CHD can take that long, and
  # guessing wrong would close a game that was about to start.
  [[ -n "$reason" ]] || return 0

  forget_play "$rom" "$started"
  record_check "$rom" broken "$reason"
  [[ "$(cut -f1 "$RUNNING_FILE" 2>/dev/null)" == "$pid" ]] && rm -f "$RUNNING_FILE"
  notify critical "$(rom_title "$rom") did not start. $reason
Details: ${LOG_FILE/#$HOME\//\~/}"
}

# The one sentence worth reading out of a failed load. FBNeo lists every file
# the romset lacks, which is the common case: a set from another version, or a
# game whose BIOS is not next to it.
