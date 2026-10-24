#!/bin/zsh
# Puts the newest Ace server code on Cloudflare: database changes first,
# then the code (deploying first broke the server once, Oct 21).
# Changes no records. Usage: update-server.sh
source "${0:A:h}/common.sh"
cd "$SERVER_DIR" || say_fail "No server folder."
say_step "Updating the server's database layout"
npx wrangler d1 migrations apply ace-sync --remote > "$HOME/Library/Caches/AceSetup-migrate.log" 2>&1 \
  || say_fail "The database update failed (see ~/Library/Caches/AceSetup-migrate.log)."
say_ok "Database up to date"
say_step "Putting the new server code on Cloudflare"
npx wrangler deploy > "$HOME/Library/Caches/AceSetup-deploy.log" 2>&1 \
  || say_fail "Cloudflare didn't take the new code (see ~/Library/Caches/AceSetup-deploy.log)."
grep -q "CLAUDE" "$HOME/Library/Caches/AceSetup-deploy.log" || print -- "INFO: The Assistant link to ace-beta-relay wasn't listed. The Assistant check in the next step will tell."
sleep 3
curl -sf -m 10 $LIVE_URL/v1/health | grep -q ok || say_fail "The server doesn't answer after the update."
say_ok "Server updated and online"
