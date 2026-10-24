#!/bin/zsh
# Setup-day step 2: the newest server code, then a fresh, empty server.
source "${0:A:h}/common.sh"
"$SETUP_DIR/update-server.sh" || exit 1
"$SETUP_DIR/fresh-server.sh" live
