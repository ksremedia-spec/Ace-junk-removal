#!/bin/zsh
# Gets the server ready for the business, once, before installing:
#  1. a new sync code (old test copies can no longer reach the server),
#  2. the new code uploaded to Cloudflare,
#  3. every test record, the test sheet link and its row tags removed,
#     and the server given a new ID (any device that synced before starts afresh),
#  4. the new address and code written into the business copy's SyncServer.txt.
# Usage: fresh-server.sh live   (the real thing)   |   fresh-server.sh local   (a dry run on the test server)
source "${0:A:h}/common.sh"
MODE=$1; [[ $MODE == live || $MODE == local ]] || say_fail "Say live or local."
cd "$SERVER_DIR" || say_fail "No server folder."
CODE=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")

say_step "Making a new sync code"
if [[ $MODE == live ]]; then
  [[ -f live-sync-code.txt ]] && cp live-sync-code.txt "live-sync-code.before-$(date +%Y%m%d-%H%M).txt"
  print -n -- "$CODE" > live-sync-code.txt
  say_step "Uploading it to Cloudflare"
  print -n -- "$CODE" | npx wrangler secret put SYNC_KEY >/dev/null 2>&1 || say_fail "Cloudflare did not take the new code."
  WHERE=--remote; URL=$LIVE_URL
else
  python3 - "$CODE" <<'PY'
import re, sys
p='.dev.vars'; s=open(p).read()
s=re.sub(r'^SYNC_KEY=.*$', 'SYNC_KEY="%s"' % sys.argv[1], s, flags=re.M)
open(p,'w').write(s)
PY
  WHERE=--local; URL=http://localhost:8787
fi
say_ok "New code in place"

say_step "Emptying the server"
npx wrangler d1 execute ace-sync $WHERE --command "DELETE FROM records; DELETE FROM sheet_rows; DELETE FROM google_link; DELETE FROM google_pending; UPDATE meta SET value = lower(hex(randomblob(16))) WHERE key = 'server_id';" >/dev/null 2>&1 || say_fail "The server could not be emptied."
say_ok "Server empty, with a new ID"

if [[ $MODE == live ]]; then
  say_step "Writing the address and code into the business copy"
  { print -- "$URL"; print -- "$CODE"; } > "$REPO/Ace/Support/SyncServer.txt"
  say_ok "SyncServer.txt updated (kept out of GitHub)"
fi
# The local test server only rereads its code when restarted.
if [[ $MODE == local ]]; then say_ok "Restart the local test server to use the new code"; exit 0; fi
# Give Cloudflare a moment, then check the new code works.
sleep 5
NEW=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $CODE" "$URL/v1/sync" -d '{"device":"setup","since":0,"changes":[]}')
[[ $NEW == 200 ]] || say_fail "The new code was refused ($NEW)."
say_ok "Server answers with the new code"

# One tiny Assistant request through the server, so the Assistant is known
# to work before anyone installs (a few hundredths of a cent).
say_step "Checking the Assistant"
B='{"model":"claude-haiku-5-5","max_tokens":5,"messages":[{"role":"user","content":"Reply with OK."}]}'
AI=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $CODE" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" "$URL/v1/claude" -d "$B")
[[ $AI == 200 ]] || say_fail "The Assistant check failed ($AI). Check the ace-beta-relay Worker and its key in Cloudflare."
say_ok "The Assistant answers through the server"
