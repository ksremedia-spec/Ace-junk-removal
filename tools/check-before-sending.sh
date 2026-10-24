#!/bin/zsh
# Checks a built Ace.app before it goes to anyone (audit Oct 21, M1;
# ship audit Oct 24, #80).
#   A test copy must not carry the live server's address and code
#   (SyncServer.txt) or the beta relay address (BetaRelay.txt).
#   The business's own copy (--business-copy) must carry SyncServer.txt and
#   must not carry BetaRelay.txt.
# Usage: tools/check-before-sending.sh path/to/Ace.app [--business-copy]
APP="$1"
[ -d "$APP" ] || { echo "No app at $APP"; exit 2; }
server=$(find "$APP" -name SyncServer.txt 2>/dev/null)
relay=$(find "$APP" -name BetaRelay.txt 2>/dev/null)
if [ "$2" = "--business-copy" ]; then
  [ -n "$relay" ] && { echo "STOP: the business copy contains the beta relay address (BetaRelay.txt)."; exit 1; }
  [ -z "$server" ] && { echo "STOP: the business copy has no server address (SyncServer.txt), so it would not sync."; exit 1; }
  echo "OK: business copy, with its server address and no beta relay."
  exit 0
fi
if [ -n "$server" ] || [ -n "$relay" ]; then
  echo "STOP: this copy contains:"; echo "$server\n$relay" | sed '/^$/d; s|.*/||'
  echo "SyncServer.txt holds the live sync code. Remove Ace/Support/SyncServer.txt and rebuild before sending a test copy."
  exit 1
fi
echo "OK to send: no server code inside."
