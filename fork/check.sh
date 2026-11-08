#!/bin/bash
# Says whether upstream has a newer T3 Code nightly than the installed fork build.
#
#   fork/check.sh            print the installed and latest versions
#   fork/check.sh --notify   also show a macOS notification, once per new nightly
#   fork/check.sh --test     show a test notification and exit
#
# It only looks; it never builds or installs anything.

set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

mode="print"
case "${1:-}" in
  "") ;;
  --notify) mode="notify" ;;
  --test)
    notify "T3 Code" "Test notification from fork/check.sh"
    note "Sent a test notification."
    exit 0
    ;;
  -h | --help)
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *) die "unknown option: $1" ;;
esac

latest_tag="$(latest_nightly_tag)"
latest="${latest_tag#v}"
installed="$(installed_version)"
note "Installed: ${installed:-not installed}"
note "Latest:    $latest"

if [[ -n "$installed" ]] &&
  (($(nightly_build_number "$installed") >= $(nightly_build_number "$latest"))); then
  note "Up to date."
  exit 0
fi
note "A newer nightly is available."

if [[ "$mode" == "notify" ]]; then
  mkdir -p "$CACHE_DIR"
  state="$CACHE_DIR/notified-tag"
  # One notification per nightly, however often the check runs.
  if [[ "$(cat "$state" 2>/dev/null || true)" != "$latest_tag" ]]; then
    notify "T3 Code update available" \
      "Nightly ${latest##*.} is out (you have ${installed##*.}). Ask Claude to rebuild."
    printf '%s\n' "$latest_tag" >"$state"
  fi
fi
