#!/bin/zsh
# Puts the business copy of Ace on one iPhone plugged into this Mac.
#  1. checks the phone trusts this Mac and has Developer Mode on,
#  2. registers it with Apple (once per phone; Ad Hoc copies only open on
#     registered phones),
#  3. signs the iPhone copy for every registered phone (Ad Hoc), checks this
#     phone is in it, and installs it, then opens Ace once.
# Research and sources: docs/setup-day.md.
# Usage: install-iphone.sh <UDID>   (list-iphones.sh gives the UDID)
source "${0:A:h}/common.sh"
UDID=$1; [[ -n $UDID ]] || say_fail "Which iPhone? Give its ID."
WORK="$HOME/Library/Caches/AceSetup"; mkdir -p "$WORK"
cd "$REPO" || say_fail "No project."
test -d "$WORK/ios.xcarchive" || say_fail "Build their copies first (step 3)."

say_step "Checking the iPhone"
J=$(mktemp -t devices)
xcrun devicectl list devices --json-output "$J" >/dev/null 2>&1
STATE=$(python3 - "$J" "$UDID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for dev in d.get("result", {}).get("devices", []):
    hw = dev.get("hardwareProperties", {}); props = dev.get("deviceProperties", {}); conn = dev.get("connectionProperties", {})
    if hw.get("udid") == sys.argv[2]:
        print(conn.get("pairingState", ""), props.get("developerModeStatus", "none"), props.get("name", "iPhone").replace(" ", "_"))
        break
PY
)
rm -f "$J"
[[ -n $STATE ]] || say_fail "This Mac can't see that iPhone. Plug it in, unlock it, and tap Trust."
read PAIRING DEVMODE NAME <<< "$STATE"
NAME=${NAME//_/ }
[[ $PAIRING == paired ]] || say_fail "$NAME doesn't trust this Mac yet. Unlock it, tap Trust, and enter the passcode."
[[ $DEVMODE == enabled ]] || say_fail "$NAME needs Developer Mode: Settings › Privacy & Security › Developer Mode › On › Restart, then Turn On after the restart."
say_ok "$NAME trusts this Mac and has Developer Mode on"

say_step "Registering $NAME with Apple (a few minutes the first time)"
xcodebuild build -project Ace.xcodeproj -scheme Ace -configuration Debug -destination "id=$UDID" \
  -derivedDataPath "$WORK/register-build" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  > "$WORK/register-$UDID.log" 2>&1 || say_fail "Apple didn't register $NAME (see $WORK/register-$UDID.log)."
say_ok "$NAME is registered"

export_copy() {
  rm -rf "$WORK/ios-export" "$WORK/ipa"
  cat > "$WORK/ios-export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>release-testing</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>6YCK9MG5RD</string>
<key>destination</key><string>export</string>
<key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$WORK/ios.xcarchive" -exportOptionsPlist "$WORK/ios-export.plist" \
    -exportPath "$WORK/ios-export" -allowProvisioningUpdates > "$WORK/ios-export.log" 2>&1 || return 1
  unzip -q -o "$WORK/ios-export/"*.ipa -d "$WORK/ipa" || return 1
  security cms -D -i "$WORK/ipa/Payload/Ace.app/embedded.mobileprovision" > "$WORK/profile.plist" 2>/dev/null
}
in_profile() { /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "$WORK/profile.plist" 2>/dev/null | grep -q "$UDID"; }

say_step "Signing the iPhone copy for $NAME"
export_copy || say_fail "The iPhone copy couldn't be signed (see $WORK/ios-export.log)."
if ! in_profile; then
  # An older Ad Hoc profile from before this phone was registered: remove it
  # so Xcode makes a new one that includes the phone.
  for p in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision(N) "$HOME/Library/MobileDevice/Provisioning Profiles/"*.mobileprovision(N); do
    security cms -D -i "$p" 2>/dev/null | grep -q "com.acejunkremoval.app" && \
      security cms -D -i "$p" 2>/dev/null | grep -q "<key>ProvisionedDevices</key>" && \
      ! security cms -D -i "$p" 2>/dev/null | grep -q "<key>get-task-allow</key>[[:space:]]*<true/>" && rm -f "$p"
  done
  export_copy || say_fail "The iPhone copy couldn't be signed (see $WORK/ios-export.log)."
  in_profile || say_fail "Apple's signing file doesn't include $NAME yet. Wait a minute and click Install again."
fi
find "$WORK/ipa/Payload/Ace.app" -name BetaRelay.txt | grep -q . && say_fail "The iPhone copy still has the beta relay inside."
find "$WORK/ipa/Payload/Ace.app" -name SyncServer.txt | grep -q . || say_fail "The iPhone copy has no server address inside."
EXPIRES=$(/usr/libexec/PlistBuddy -c "Print :ExpirationDate" "$WORK/profile.plist" 2>/dev/null)
say_ok "Signed for $NAME (good until ${EXPIRES:-unknown})"

say_step "Installing Ace on $NAME"
xcrun devicectl device install app --device "$UDID" "$WORK/ipa/Payload/Ace.app" > "$WORK/install-$UDID.log" 2>&1 \
  || say_fail "Ace didn't install on $NAME (see $WORK/install-$UDID.log). Keep it unlocked and try again."
say_ok "Ace is on $NAME"
xcrun devicectl device process launch --device "$UDID" com.acejunkremoval.app >/dev/null 2>&1 \
  && say_ok "Ace opened on $NAME" \
  || print -- "INFO: Open Ace on $NAME by hand (it needs internet the first time)."
[[ -n $EXPIRES ]] && print -- "INFO: The copy stops opening after $EXPIRES. Install again before then; never delete the app first."
