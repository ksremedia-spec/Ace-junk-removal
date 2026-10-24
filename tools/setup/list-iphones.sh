#!/bin/zsh
# The iPhones this Mac can see, one per line: id|name|model|connection|iOS|developer mode
source "${0:A:h}/common.sh"
J=$(mktemp -t devices)
xcrun devicectl list devices --json-output "$J" >/dev/null 2>&1
python3 - "$J" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {}); props = dev.get("deviceProperties", {}); conn = dev.get("connectionProperties", {})
    if hw.get("platform") != "iOS" or hw.get("reality") != "physical": continue
    print("|".join([hw.get("udid", ""), props.get("name", ""), hw.get("marketingName", hw.get("productType", "")),
                    conn.get("tunnelState", conn.get("pairingState", "")), props.get("osVersionNumber", ""),
                    str(props.get("developerModeStatus", ""))]))
PY
rm -f "$J"
