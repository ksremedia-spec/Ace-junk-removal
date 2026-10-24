#!/bin/zsh
# Shared settings for the setup steps (run by "Ace Setup" or by hand).
SETUP_DIR="${0:A:h}"
REPO="${0:A:h:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$HOME/Desktop/Xcode 2.app/Contents/Developer}"
export PATH="$HOME/.ace-tools/node-v24.21.0-darwin-arm64/bin:$PATH"
SERVER_DIR="$REPO/cloudflare/ace-sync"
# The live server's address, kept out of the public repository (.gitignore).
LIVE_URL="$(head -1 "$SETUP_DIR/live-url.txt" 2>/dev/null | tr -d '[:space:]')"
[[ -n $LIVE_URL ]] || { print -- "FAIL: tools/setup/live-url.txt is missing (the live server's address, one line)."; exit 1; }
OUT="$HOME/Desktop/Ace for the business"
say_step() { print -- "STEP: $*"; }
say_ok() { print -- "OK: $*"; }
say_fail() { print -- "FAIL: $*"; exit 1; }
