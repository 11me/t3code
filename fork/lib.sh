# Shared settings and helpers for the fork scripts. Sourced, not run.
# shellcheck shell=bash
# shellcheck disable=SC2034 # The settings below are read by the scripts that source this file.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_REPO="pingdotgg/t3code"
# Upstream nightlies plus your changes. Builds come from it; `main` mirrors the nightlies.
BASE_BRANCH="patched"
APP_NAME="T3 Code (Nightly)"
APP_PATH="/Applications/$APP_NAME.app"
CACHE_DIR="${T3CODE_FORK_CACHE:-$HOME/.cache/t3code-fork}"
NODE_VERSION="26.12.1"

note() { printf '%s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Newest published upstream nightly tag, e.g. v0.1.8-nightly.20261104.4179.
latest_nightly_tag() {
  local tag
  tag="$(curl -fsSL -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$UPSTREAM_REPO/releases?per_page=30" |
    grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}\.[0-9]+"' |
    head -n 1 | sed -E 's/.*"(v[^"]+)"$/\1/')" || true
  [[ -n "$tag" ]] || die "could not read the latest nightly from GitHub"
  printf '%s\n' "$tag"
}

# Version of the installed fork app, empty when it is not installed.
installed_version() {
  [[ -d "$APP_PATH" ]] || return 0
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP_PATH/Contents/Info.plist" 2>/dev/null || true
}

# The trailing build number of a nightly version: 0.1.8-nightly.20261104.4179 -> 4179.
nightly_build_number() { printf '%s\n' "${1##*.}"; }

app_running() { pgrep -f "/$1.app/Contents/MacOS/" >/dev/null; }

quit_app() {
  local name="$1"
  app_running "$name" || return 0
  note "Quitting $name ..."
  osascript -e "quit app \"$name\"" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    app_running "$name" || return 0
    sleep 1
  done
  die "$name is still running. Quit it and try again."
}

notify() {
  local title="$1" message="$2"
  osascript -e "display notification \"${message//\"/\\\"}\" with title \"${title//\"/\\\"}\"" \
    >/dev/null 2>&1 || true
}
