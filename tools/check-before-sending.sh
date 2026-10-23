#!/bin/zsh
# Checks a built Ace.app before it goes to anyone (audit Oct 21, M1):
# refuses if the live server's address and code (SyncServer.txt) or the
# beta relay address are inside, unless told the copy is the business's own.
# Usage: tools/check-before-sending.sh path/to/Ace.app [--business-copy]
APP="$1"
[ -d "$APP" ] || { echo "No app at $APP"; exit 2; }
found=$(find "$APP" \( -name SyncServer.txt -o -name BetaRelay.txt \) 2>/dev/null)
if [ -n "$found" ] && [ "$2" != "--business-copy" ]; then
  echo "STOP: this copy contains:"; echo "$found" | sed 's|.*/||'
  echo "SyncServer.txt holds the live sync code. Remove Ace/Support/SyncServer.txt and rebuild before sending a beta."
  exit 1
fi
echo "OK to send: no server code inside."
