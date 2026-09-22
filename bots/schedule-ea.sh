#!/usr/bin/env bash
# Install (or remove) the launchd job that pings @ea in a channel on a schedule.
# Usage: bots/schedule-ea.sh install <channel-uuid> [model]   |   bots/schedule-ea.sh remove
# Schedule: weekdays 06,09,12,15,18; Saturday and Sunday 12:00. Message: "@ea use <model>: /ea"
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; BIN="${BUZZ_DIR:-$HOME/github/buzz}/target/debug"
LABEL=com.agentic.ea-schedule; PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
case "${1:-}" in
  install)
    CH="${2:?channel uuid}"; MODEL="${3:-opus}"; EA_PK=$(awk -F= '/^PK=/{print $2}' "$HERE/keys/ea.key")
    [[ -f "$HERE/keys/scheduler.key" ]] || "$HERE/bots.sh" keygen scheduler   # posts must NOT come from ea's own key: buzz-acp ignores self-authored events
    SCHED_SK=$(awk -F= '/^SK=/{print $2}' "$HERE/keys/scheduler.key")
    cat >"$HERE/.build/ea-schedule.sh" <<EOS
#!/usr/bin/env bash
export BUZZ_RELAY_URL=http://localhost:3000 BUZZ_PRIVATE_KEY=$SCHED_SK
exec "$BIN/buzz" messages send --channel "$CH" --mention "$EA_PK" --content "@ea use $MODEL: /ea"
EOS
    chmod 700 "$HERE/.build/ea-schedule.sh"
    { echo '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>'
      echo "<key>Label</key><string>$LABEL</string><key>ProgramArguments</key><array><string>$HERE/.build/ea-schedule.sh</string></array>"
      echo "<key>StandardOutPath</key><string>$HERE/logs/ea-schedule.log</string><key>StandardErrorPath</key><string>$HERE/logs/ea-schedule.log</string>"
      echo '<key>StartCalendarInterval</key><array>'
      for wd in 1 2 3 4 5; do for h in 6 9 12 15 18; do echo "<dict><key>Weekday</key><integer>$wd</integer><key>Hour</key><integer>$h</integer><key>Minute</key><integer>0</integer></dict>"; done; done
      for wd in 0 6; do echo "<dict><key>Weekday</key><integer>$wd</integer><key>Hour</key><integer>12</integer><key>Minute</key><integer>0</integer></dict>"; done
      echo '</array></dict></plist>'; } >"$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; launchctl bootstrap "gui/$(id -u)" "$PLIST"; echo "installed $LABEL → channel $CH, model $MODEL"; launchctl print "gui/$(id -u)/$LABEL" | grep -E 'state|next' | head -3 ;;
  remove) launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true; rm -f "$PLIST"; echo "removed $LABEL" ;;
  *) echo "usage: $0 install <channel-uuid> [model] | remove"; exit 1 ;;
esac
