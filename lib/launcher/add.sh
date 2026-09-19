# shellcheck shell=bash
# arcade-launcher: adding romsets, and checking which start.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Adding games
#
# A romset dropped on the panel (or passed to --add) is copied into ROM_DIR and
# then actually loaded: RetroArch runs the core for a couple of frames with no
# window and no sound, and the same log lines that tell a failed launch apart
# say whether it runs. Only the ones that do are kept. It is tested from inside
# ROM_DIR because that is where the BIOS a game needs is looked for.
# --------------------------------------------------------------------------

sibling_command() {
  local sibling="${SELF%/*}/$1"
  if [[ -x "$sibling" ]]; then printf '%s\n' "$sibling"
  elif command -v "$1" >/dev/null 2>&1; then command -v "$1"
  fi
  return 0
}

# Loads a romset headless and prints why it will not run, or nothing if it will.
probe_rom() {
  local rom="$1" cfg log reason=""
  cfg="$(mktemp --suffix=.cfg)" log="$(mktemp)"
  # A test is not a game played: no window, no sound, nothing in RetroArch's
  # history or play time, and its config left exactly as it was.
  {
    arcade_base_lines
    printf '%s\n' 'video_driver = "null"' 'audio_driver = "null"' \
      'history_list_enable = "false"' 'content_runtime_log = "false"' \
      'content_runtime_log_aggregate = "false"'
  } >"$cfg"
  local -a cmd=("$RETROARCH_BIN" --verbose --max-frames=2 -L "$CORE_PATH")
  [[ -n "$RETROARCH_CONFIG" ]] && cmd+=(--config "$RETROARCH_CONFIG")
  cmd+=(--appendconfig "$cfg" "$rom")
  timeout 30 "${cmd[@]}" >"$log" 2>&1 </dev/null || true

  local chunk
  chunk="$(cat -- "$log")"
  # Missing files first: FBNeo still reports a picture for its own "files
  # are missing" screen. "Unloading game" is not a failure here -- every test
  # run ends with it after its two frames.
  if grep -qE 'is required$|Failed to load content' <<<"$chunk"; then
    reason="$(launch_failure "$chunk")"
    reason="${reason:-RetroArch could not load it.}"
  elif ! grep -q '\[Core\] Geometry:' <<<"$chunk"; then
    reason="$(launch_failure "$chunk")"
    reason="${reason:-RetroArch could not load it with this core.}"
  fi
  rm -f -- "$cfg" "$log"
  printf '%s' "$reason"
}

# ---- whether a romset starts

# "size<TAB>mtime" of a file: what a check result is tied to.
file_stamp() { stat --printf '%s\t%Y' -- "$1" 2>/dev/null; }

# Remember what was found out about one romset, replacing what was known.
record_check() {
  local path="$1" verdict="$2" reason="${3//$'\t'/ }" stamp tmp
  stamp="$(file_stamp "$path")" || return 0
  mkdir -p "${CHECK_FILE%/*}" 2>/dev/null || return 0
  [[ -e "$CHECK_FILE" ]] || : >"$CHECK_FILE" 2>/dev/null || return 0
  tmp="$(mktemp "$CHECK_FILE.XXXXXX")" || return 0
  { awk -F'\t' -v p="$path" '$1 != p' "$CHECK_FILE"
    printf '%s\t%s\t%s\t%s\n' "$path" "$stamp" "$verdict" "${reason//$'\n'/ }"
  } >"$tmp" && mv -f "$tmp" "$CHECK_FILE" || rm -f "$tmp"
}

# "path<TAB>ok|broken<TAB>reason" for every result still about the file that
# is there now; a romset replaced since it was checked is simply not known.
check_lines() {
  [[ -r "$CHECK_FILE" ]] || return 0
  local path size mtime verdict reason now
  while IFS=$'\t' read -r path size mtime verdict reason; do
    now="$(file_stamp "$path")" || continue
    [[ "$now" == "$size"$'\t'"$mtime" ]] && printf '%s\t%s\t%s\n' "$path" "$verdict" "$reason"
  done <"$CHECK_FILE"
}

# Test-load every game in ROM_DIR (or the romsets given), the way adding one
# does, and remember which start. One already checked is not checked again
# unless it changed, or --all is given. Prints "checking<TAB>name<TAB>n<TAB>of"
# before each and "ok|broken|known-ok|known-broken<TAB>path<TAB>reason" after.
cmd_check() {
  local all=0 path rom index=0 reason known verdict
  [[ "${1-}" == --all ]] && { all=1; shift; }
  local -a paths=()
  if (($#)); then
    for path in "$@"; do
      local wanted="$path"
      [[ "$path" == */* ]] || path="$(resolve_rom_name "$path")" || { printf 'broken\t%s\t%s\n' "$wanted" "no such romset"; continue; }
      paths+=("$path")
    done
  else
    while IFS= read -r path; do
      rom="${path##*/}"; rom="${rom%.*}"
      is_bios_set "$rom" || paths+=("$path")
    done < <(find_roms)
  fi
  local -A seen=()
  while IFS=$'\t' read -r path verdict reason; do seen["$path"]="$verdict"$'\t'"$reason"; done < <(check_lines)
  for path in "${paths[@]}"; do
    index=$((index + 1))
    if ((!all)) && [[ -n "${seen[$path]-}" ]]; then
      known="${seen[$path]}"
      printf 'known-%s\t%s\t%s\n' "${known%%$'\t'*}" "$path" "${known#*$'\t'}"
      continue
    fi
    printf 'checking\t%s\t%d\t%d\n' "${path##*/}" "$index" "${#paths[@]}"
    reason="$(cd -- "$ROM_DIR" 2>/dev/null && probe_rom "$path")"
    if [[ -n "$reason" ]]; then
      record_check "$path" broken "$reason"
      printf 'broken\t%s\t%s\n' "$path" "$reason"
    else
      record_check "$path" ok ""
      printf 'ok\t%s\t\n' "$path"
    fi
  done
  return 0
}

# Is this romset a BIOS or device set rather than a game?
is_bios_set() {
  local rom="$1" title set
  for set in "${BIOS_SETS[@]}"; do [[ "$set" == "$rom" ]] && return 0; done
  title="$(title_sources | awk -F'\t' -v rom="$rom" '!found && $1 == rom && NF >= 2 { title = tolower($2); found = 1 } END { print title }')"
  [[ "$title" =~ bios\)?$ || "$title" =~ internal\ p?rom$ ]]
}

# One "result<TAB>name<TAB>detail" line per file, each after a
# "checking<TAB>name<TAB>n<TAB>of" line announcing it:
#   added      a game, copied in and tested       detail: its title
#   bios       a BIOS or device set, copied in    detail: its title
#   exists     already in ROM_DIR, identical      detail: its title
#   conflict   a different file of that name is there; nothing replaced
#   rejected   copied in, would not run, taken out again   detail: why
#   skipped    not a romset at all                detail: why
cmd_add() {
  local file name rom dest ext title reason ok_ext added=() arg index=0
  mkdir -p -- "$ROM_DIR" || die "$EX_NO_ROM_DIR" "cannot create $ROM_DIR"

  # A folder stands for the romsets in it (not its subfolders): dropping a
  # download folder adds the games in it without picking them one by one.
  local -a files=() pattern=()
  for ext in $ROM_EXTS; do
    ((${#pattern[@]})) && pattern+=(-o)
    pattern+=(-iname "*.$ext")
  done
  for arg in "$@"; do
    if [[ -d "$arg" ]]; then
      while IFS= read -r -d '' file; do files+=("$file"); done < <(
        find "$arg" -maxdepth 1 -type f \( "${pattern[@]}" \) -print0 | sort -z)
    else
      files+=("$arg")
    fi
  done

  for file in "${files[@]}"; do
    index=$((index + 1))
    # Said before each one, so a long drop can be followed as it goes.
    printf 'checking\t%s\t%d\t%d\n' "${file##*/}" "$index" "${#files[@]}"
    name="${file##*/}"
    rom="${name%.*}"
    ext="${name##*.}"
    ok_ext=0
    for want in $ROM_EXTS; do [[ "${ext,,}" == "${want,,}" ]] && ok_ext=1; done
    if [[ ! -f "$file" ]]; then
      printf 'skipped\t%s\t%s\n' "$name" "not a file"
      continue
    fi
    if ((!ok_ext)); then
      printf 'skipped\t%s\t%s\n' "$name" "not a romset (${ROM_EXTS// /, })"
      continue
    fi

    dest="$ROM_DIR/$name"
    title="$(rom_title "$rom")"
    if [[ -e "$dest" ]]; then
      if cmp -s -- "$file" "$dest"; then
        printf 'exists\t%s\t%s\n' "$name" "$title"
      else
        printf 'conflict\t%s\t%s\n' "$name" "a different $name is already in your collection"
      fi
      continue
    fi

    cp -- "$file" "$dest" || { printf 'rejected\t%s\t%s\n' "$name" "could not copy it into $ROM_DIR"; continue; }

    if is_bios_set "$rom"; then
      printf 'bios\t%s\t%s\n' "$name" "$title"
      continue
    fi

    reason="$(probe_rom "$dest")"
    if [[ -n "$reason" ]]; then
      rm -f -- "$dest"
      printf 'rejected\t%s\t%s\n' "$name" "$reason"
      continue
    fi
    record_check "$dest" ok ""
    printf 'added\t%s\t%s\n' "$name" "$title"
    added+=("$rom")
  done

  # Artwork for what came in, so the tile is dressed the moment it appears.
  local artwork
  artwork="$(sibling_command arcade-artwork)"
  if ((${#added[@]})) && [[ -n "$artwork" ]]; then
    "$artwork" "${added[@]}" >/dev/null 2>&1 || true
  fi
  return 0
}

launch_failure() {
  local chunk="$1" missing names
  missing="$(grep -c 'is required' <<<"$chunk" || true)"
  if ((missing > 0)); then
    names="$(grep 'is required' <<<"$chunk" | grep -oE 'with name [^ ]+' | head -n3 | cut -d' ' -f3 |
      paste -sd, - | sed 's/,/, /g')"
    printf '%s file%s missing from the romset (%s%s) -- it may be for another version, or need its BIOS.\n' \
      "$missing" "$( ((missing == 1)) && echo ' is' || echo 's are')" "$names" "$( ((missing > 3)) && echo ', ...')"
    return 0
  fi
  grep -E 'ERROR' <<<"$chunk" | tail -n1 | sed -E 's/^(\[[^]]*\] *)+//' || true
}

# Resolve a bare short name ("bublbobl") to a path inside ROM_DIR.
resolve_rom_name() {
  local wanted="$1" path base
  while IFS= read -r path; do
    base="${path##*/}"
    [[ "${base%.*}" == "$wanted" || "$base" == "$wanted" ]] && {
      printf '%s\n' "$path"
      return 0
    }
  done < <(find_roms)
  return 1
}
