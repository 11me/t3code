#!/bin/bash
# Installs the daily update check as a launchd job (10:00; runs on wake if the Mac slept).
#
#   fork/notifier.sh install     write the job and load it
#   fork/notifier.sh uninstall   unload and delete it
#   fork/notifier.sh status      show whether it is loaded
#   fork/notifier.sh run         run the job now, as launchd would

set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

LABEL="personal.t3code-fork.check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

write_plist() {
  mkdir -p "$(dirname "$PLIST")" "$CACHE_DIR"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$REPO_DIR/fork/check.sh</string>
    <string>--notify</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>10</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$CACHE_DIR/check.log</string>
  <key>StandardErrorPath</key>
  <string>$CACHE_DIR/check.log</string>
</dict>
</plist>
EOF
  plutil -lint "$PLIST" >/dev/null
}

case "${1:-}" in
  install)
    write_plist
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    note "Installed $LABEL: checks daily at 10:00. Log: $CACHE_DIR/check.log"
    ;;
  uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"
    note "Removed $LABEL."
    ;;
  status)
    if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
      note "Loaded: $PLIST"
    else
      note "Not loaded."
    fi
    ;;
  run) launchctl kickstart "$DOMAIN/$LABEL" ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
