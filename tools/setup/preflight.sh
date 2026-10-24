#!/bin/zsh
# Checks this Mac and the Ace server are ready for setup day. Changes nothing.
source "${0:A:h}/common.sh"
fails=0
check() { if ( eval "$2" ) >/dev/null 2>&1; then say_ok "$1"; else print -- "FAIL: $1 — $3"; fails=$((fails+1)); fi; }
say_step "Checking this Mac"
check "Xcode is here" "xcodebuild -version" "Xcode should be at ~/Desktop/Xcode 2.app."
check "Apple signing is set up" "security find-identity -v -p codesigning | grep -q 'Apple Development'" "Open Xcode › Settings › Accounts and sign in to the Apple developer account."
check "Cloudflare's tool is signed in" "cd '$SERVER_DIR' && npx wrangler whoami | grep -q 'logged in'" "Run 'npx wrangler login' in cloudflare/ace-sync (one time)."
check "The business copy has its server address" "test -s '$REPO/Ace/Support/SyncServer.txt'" "Ace/Support/SyncServer.txt is missing; step 2 makes it."
check "The business copy is not a beta" "grep -q 'static let isBeta = false' '$REPO/Ace/Support/Beta.swift'" "Beta mode is on in Ace/Support/Beta.swift."
check "The beta relay address is out of the app" "! test -e '$REPO/Ace/Support/BetaRelay.txt'" "Move Ace/Support/BetaRelay.txt to cloudflare/beta-relay/."
check "There's room on the disk (5 GB)" "test \$(df -g ~ | awk 'NR==2{print \$4}') -ge 5" "Free some disk space."
say_step "Checking the Ace server"
check "The Ace server is online" "curl -sf -m 10 $LIVE_URL/v1/health | grep -q ok" "No answer from the server. Check this Mac's internet."
check "Google sign-in pages are up" "curl -sf -m 10 $LIVE_URL/privacy | grep -q Ace" "The server's privacy page did not load."
print -- "INFO: Google sign-in is published (In production) since Oct 24, so Ashley's Gmail can connect."
say_step "Checking for iPhones"
n=$("$SETUP_DIR/list-iphones.sh" | wc -l | tr -d ' ')
print -- "INFO: $n iPhone(s) known to this Mac. Theirs show up when plugged in."
(( fails == 0 )) || exit 1
