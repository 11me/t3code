#!/bin/bash
# Installs a fork build as /Applications/T3 Code (Nightly).app. Run it from Terminal, not from
# inside T3 Code: it quits the app first, which would end that session.
#
#   fork/install.sh                install the newest build from fork/build.sh
#   fork/install.sh path/to.dmg    install a specific DMG
#   fork/install.sh --open ...     open the app afterwards
#   fork/install.sh --rollback     put the previously installed version back
#
# The replaced version is kept in ~/.cache/t3code-fork/previous/ for --rollback.

set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

open_after=false
rollback=false
dmg=""
for arg in "$@"; do
  case "$arg" in
    --open) open_after=true ;;
    --rollback) rollback=true ;;
    -h | --help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) die "unknown option: $arg" ;;
    *) dmg="$arg" ;;
  esac
done

if [[ -n "${T3CODE_THREAD_ID:-}" ]]; then
  die "this is running inside T3 Code. Run it from Terminal: it quits T3 Code, which would end this session."
fi

previous="$CACHE_DIR/previous/$APP_NAME.app"

if [[ "$rollback" == true ]]; then
  [[ -d "$previous" ]] || die "no previous version to roll back to"
  quit_app "$APP_NAME"
  swap="$CACHE_DIR/previous/swap.app"
  rm -rf "$swap"
  [[ -d "$APP_PATH" ]] && mv "$APP_PATH" "$swap"
  mv "$previous" "$APP_PATH"
  [[ -d "$swap" ]] && mv "$swap" "$previous"
  note "Rolled back to $(installed_version)."
  [[ "$open_after" == true ]] && open "$APP_PATH"
  exit 0
fi

if [[ -z "$dmg" ]]; then
  dmg="$(find "$CACHE_DIR/out" -name '*.dmg' -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n 1)"
  [[ -n "$dmg" ]] || die "no build found; run fork/build.sh first"
fi
[[ -f "$dmg" ]] || die "not found: $dmg"
note "Installing $(basename "$dmg")"

staging="$(mktemp -d)"
mount_dir="$staging/mnt"
# shellcheck disable=SC2329 # Runs from the EXIT trap.
cleanup() {
  hdiutil detach -force "$mount_dir" >/dev/null 2>&1 || true
  rm -rf "$staging"
}
trap cleanup EXIT

mkdir -p "$mount_dir"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_dir" >/dev/null
ditto "$mount_dir/$APP_NAME.app" "$staging/$APP_NAME.app"
hdiutil detach "$mount_dir" >/dev/null
# Packaging leaves the unsigned bundle's seal broken; an ad hoc signature makes it valid again.
codesign --force --deep --sign - "$staging/$APP_NAME.app" 2>/dev/null
codesign --verify --deep --strict "$staging/$APP_NAME.app"
xattr -dr com.apple.quarantine "$staging/$APP_NAME.app" 2>/dev/null || true

quit_app "$APP_NAME"
mkdir -p "$(dirname "$previous")"
rm -rf "$previous"
[[ -d "$APP_PATH" ]] && mv "$APP_PATH" "$previous"
mv "$staging/$APP_NAME.app" "$APP_PATH"
note "Installed $(installed_version). The replaced version is kept for --rollback."

if app_running "T3 Code (Beta)"; then
  note "T3 Code (Beta) is running. Both apps share one data folder and lock: quit it first."
  open_after=false
fi
[[ "$open_after" == true ]] && open "$APP_PATH"
exit 0
