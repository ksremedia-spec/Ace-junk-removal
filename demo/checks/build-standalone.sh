#!/bin/sh
# Builds demo/build/Ace-demo.html: the demo page wrapped in the same page
# skeleton claude.ai adds when it publishes, so it opens in any browser.
cd "$(dirname "$0")/.." || exit 1
mkdir -p build
{ cat checks/standalone-head.html; cat app-demo/index.html; printf '</body></html>\n'; } > build/Ace-demo.html
echo "Built demo/build/Ace-demo.html"
