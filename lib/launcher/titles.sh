# shellcheck shell=bash
# arcade-launcher: the title cache from the libretro databases.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Titles
# --------------------------------------------------------------------------

pad_command() {
  local sibling="${SELF%/*}/arcade-pad"
  if [[ -x "$sibling" ]]; then printf '%s\n' "$sibling"
  elif command -v arcade-pad >/dev/null 2>&1; then command -v arcade-pad
  fi
  return 0
}

rdb_dump_command() {
  local sibling="${SELF%/*}/arcade-rdb-dump"
  if [[ -x "$sibling" ]]; then
    printf '%s\n' "$sibling"
  elif command -v arcade-rdb-dump >/dev/null 2>&1; then
    command -v arcade-rdb-dump
  fi
  return 0
}

# Regenerate the RDB-derived title cache. Written to a temp file first so an
# interrupted run never leaves a truncated cache behind.
rebuild_cache() {
  local dumper tmp
  dumper="$(rdb_dump_command)"

  if [[ -z "$dumper" ]]; then
    log "arcade-rdb-dump not found; falling back to raw ROM filenames"
    return 1
  fi

  mkdir -p "${CACHE_FILE%/*}"
  tmp="$(mktemp "${CACHE_FILE}.XXXXXX")"

  if "$dumper" >"$tmp" 2>>"$LOG_FILE" && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$CACHE_FILE"
    return 0
  fi

  rm -f "$tmp"
  log "could not build title cache; see $LOG_FILE"
  return 1
}

cache_is_stale() {
  [[ ! -s "$CACHE_FILE" ]] && return 0
  # Caches from before 1.4 hold only titles; the panel wants year and maker.
  head -n1 -- "$CACHE_FILE" | awk -F'\t' '{ exit (NF >= 4) }' && return 0

  local db
  for db in /usr/share/libretro/database/rdb/*.rdb \
    "$HOME/.config/retroarch/database/rdb"/*.rdb; do
    [[ -f "$db" && "$db" -nt "$CACHE_FILE" ]] && return 0
  done

  return 1
}

# Print "romname<TAB>title" for every mapping we know, user overrides first so a
# later awk can let the first occurrence win.
#
# A \035 line separates your own titles from the rest, so the listing can tell
# a set you have named yourself from one the database named.
#
# A \037 line comes before the database's own titles, which the panel groups
# the versions of a game by: "Street Fighter III: New Generation (Japan
# 970204)" and "(USA 970204)" are one game, whatever either is called here.
title_sources() {
  title_lines "$TITLES_FILE"
  printf '\035\n'
  title_lines "$SHIPPED_TITLES_FILE"
  printf '\037\n'
  [[ -r "$CACHE_FILE" ]] && cat -- "$CACHE_FILE" || true
}

title_lines() {
  [[ -r "$1" ]] || return 0
  grep -v '^[[:space:]]*#' -- "$1" | grep -v '^[[:space:]]*$' || true
}
