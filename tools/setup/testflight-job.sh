#!/bin/zsh
# The automatic TestFlight upload. launchd runs this once a day; it uploads
# only when the last upload is 60 or more days old (a TestFlight copy stops
# opening after 90), building the last committed version. A failure shows a
# notice on this Mac and is tried again the next day.
# Install or remove the daily check: testflight-job.sh install | remove
source "${0:A:h}/common.sh"
LABEL=com.acejunkremoval.testflight
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
WORK="$HOME/Library/Caches/AceSetup"; mkdir -p "$WORK"
notify() { osascript -e "display notification \"$1\" with title \"Ace TestFlight\"" >/dev/null 2>&1; }

case $1 in
  install)
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>/bin/zsh</string><string>${0:A}</string></array>
<key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
<key>StandardOutPath</key><string>$WORK/testflight-job.log</string>
<key>StandardErrorPath</key><string>$WORK/testflight-job.log</string>
</dict></plist>
PLIST
    launchctl bootout gui/$(id -u) "$PLIST" >/dev/null 2>&1
    launchctl bootstrap gui/$(id -u) "$PLIST" || say_fail "The daily check couldn't be turned on."
    say_ok "Automatic TestFlight uploads are on (checked daily at 3:30 AM; uploads every 60 days)"
    exit 0 ;;
  remove)
    launchctl bootout gui/$(id -u) "$PLIST" >/dev/null 2>&1; rm -f "$PLIST"
    say_ok "Automatic TestFlight uploads are off"; exit 0 ;;
esac

LAST=$(cat "$WORK/last-testflight.txt" 2>/dev/null || echo 0)
AGE=$(( ($(date +%s) - LAST) / 86400 ))
print -- "$(date): last upload $AGE days ago"
(( AGE < 60 )) && exit 0
if "$SETUP_DIR/upload-testflight.sh" --from-commit; then
  notify "A fresh copy of Ace was uploaded to TestFlight."
else
  notify "The TestFlight upload failed. It tries again tomorrow; the current copy keeps working until day 90."
  exit 1
fi
