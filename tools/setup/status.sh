#!/bin/zsh
# What the live server holds now: records, devices, the Google Sheet link.
# Usage: status.sh [local]
source "${0:A:h}/common.sh"
cd "$SERVER_DIR" || exit 1
WHERE=--remote; URL=$LIVE_URL; CODEFILE=live-sync-code.txt
if [[ $1 == local ]]; then WHERE=--local; URL=http://localhost:8787; fi
q() { npx wrangler d1 execute ace-sync $WHERE --json --command "$1" 2>/dev/null | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)[0]['results']))"; }
print -- "SERVER: $(curl -s -m 10 $URL/v1/health)"
print -- "RECORDS: $(q "SELECT type, COUNT(*) AS n FROM records WHERE deleted = 0 GROUP BY type")"
print -- "DEVICES: $(q "SELECT COUNT(DISTINCT device) AS n FROM records WHERE device NOT IN ('', 'sheet', 'check', 'x', 'test', 'phone')")"
print -- "SHEET: $(q "SELECT sheet_name, paused, last_error, last_run FROM google_link")"
