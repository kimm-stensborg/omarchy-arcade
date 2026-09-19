# shellcheck shell=bash
# arcade-launcher: printing, notifying and failing.
# Sourced by bin/arcade-launcher, in the order it lists; not run on its own.

# --------------------------------------------------------------------------
# Output helpers
# --------------------------------------------------------------------------

log() { printf '%s: %s\n' "$PROGRAM" "$*" >&2; }

notify() {
  local urgency="$1" body="$2"
  if command -v omarchy-notification-send >/dev/null 2>&1; then
    omarchy-notification-send -u "$urgency" "Arcade launcher" "$body" || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -u "$urgency" "Arcade launcher" "$body" || true
  fi
}

# Fail with a message on stderr *and* on the desktop, since the usual caller is
# a keybinding with no terminal attached.
die() {
  local code="$1"
  shift
  log "$*"
  notify critical "$*"
  exit "$code"
}
