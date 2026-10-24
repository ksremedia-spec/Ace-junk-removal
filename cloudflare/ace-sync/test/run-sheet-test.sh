#!/bin/zsh
# Runs the Google Sheet link test on this Mac: the stand-in Google on port
# 8790, a separate test server on port 8788 with its own empty database
# (.wrangler/test-state), then test/sheet-test.mjs. Nothing touches the
# main local server (port 8787) or any real Google account.
cd "$(dirname "$0")/.."
export PATH="$HOME/.ace-tools/node-v24.21.0-darwin-arm64/bin:$PATH"
STATE=.wrangler/test-state
# A made-up sync code for the test server only (the real one is never read).
export SYNC_KEY=sheet-test-only
rm -rf $STATE
npx wrangler d1 migrations apply ace-sync --local --persist-to $STATE >/dev/null 2>&1
node test/fake-google.mjs > /tmp/ace-fake-google.log 2>&1 &
FAKE=$!
npx wrangler dev --port 8788 --persist-to $STATE \
  --var SYNC_KEY:$SYNC_KEY --var GOOGLE_TEST_URL:http://localhost:8790 --var GOOGLE_CLIENT_ID:test-client \
  --var GOOGLE_CLIENT_SECRET:test-secret --var PUBLIC_URL:http://localhost:8788 > /tmp/ace-test-server.log 2>&1 &
SERVER=$!
for i in {1..60}; do grep -q "Ready on" /tmp/ace-test-server.log && break; sleep 0.5; done
node ${TEST:-test/sheet-test.mjs}
RESULT=$?
kill $SERVER $FAKE 2>/dev/null
pkill -f "wrangler dev --port 8788" 2>/dev/null
exit $RESULT
