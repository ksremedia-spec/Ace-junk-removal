#!/bin/zsh
# Builds the business copies of Ace (Release, with the live server's address
# and code from Ace/Support/SyncServer.txt inside):
#   Mac:    archived, signed with Developer ID, notarized by Apple, in Ace.dmg
#   iPhone: archived and uploaded to TestFlight (upload-testflight.sh)
# Output: ~/Desktop/Ace for the business/
# Usage: build-business.sh [mac|iphone]   (both when left out)
source "${0:A:h}/common.sh"
WHAT=${1:-both}
WORK="$HOME/Library/Caches/AceSetup"; mkdir -p "$WORK" "$OUT"
cd "$REPO" || say_fail "No project."
test -s Ace/Support/SyncServer.txt || say_fail "Ace/Support/SyncServer.txt is missing. Do step 2 first."
grep -q 'static let isBeta = false' Ace/Support/Beta.swift || say_fail "Beta mode is still on in Ace/Support/Beta.swift."

if [[ $WHAT == both || $WHAT == mac ]]; then
  say_step "Building the Mac copy"
  rm -rf "$WORK/mac.xcarchive" "$WORK/mac-export"
  xcodebuild archive -project Ace.xcodeproj -scheme Ace -configuration Release -destination 'generic/platform=macOS' \
    -archivePath "$WORK/mac.xcarchive" -allowProvisioningUpdates > "$WORK/mac-archive.log" 2>&1 || say_fail "The Mac build failed (see $WORK/mac-archive.log)."
  say_ok "Mac copy built"
  say_step "Sending it to Apple to be checked (notarized). Can take 5–15 minutes"
  cat > "$WORK/mac-export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>6YCK9MG5RD</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$WORK/mac.xcarchive" -exportOptionsPlist "$WORK/mac-export.plist" \
    -exportPath "$WORK/mac-export" -allowProvisioningUpdates > "$WORK/mac-export.log" 2>&1 || say_fail "Apple didn't take the Mac copy (see $WORK/mac-export.log)."
  for i in {1..60}; do
    if xcodebuild -exportNotarizedApp -archivePath "$WORK/mac.xcarchive" -exportPath "$WORK/mac-notarized" > "$WORK/mac-notary.log" 2>&1; then break; fi
    (( i == 60 )) && say_fail "Apple hasn't finished checking after 30 minutes. Click Build again later (see $WORK/mac-notary.log)."
    sleep 30
  done
  APP="$WORK/mac-notarized/Ace.app"
  test -d "$APP" || say_fail "The notarized Mac copy wasn't found."
  xcrun stapler validate "$APP" >/dev/null 2>&1 && say_ok "Apple checked it (notarized)" || print -- "INFO: notarized, but the ticket couldn't be confirmed offline"
  find "$APP" -name BetaRelay.txt | grep -q . && say_fail "The Mac copy still has the beta relay inside."
  find "$APP" -name SyncServer.txt | grep -q . || say_fail "The Mac copy has no server address inside."
  say_step "Making Ace.dmg"
  rm -rf "$WORK/dmg" && mkdir -p "$WORK/dmg" && cp -R "$APP" "$WORK/dmg/" && ln -s /Applications "$WORK/dmg/Applications"
  rm -f "$OUT/Ace.dmg"
  hdiutil create -volname "Ace" -srcfolder "$WORK/dmg" -ov -format UDZO "$OUT/Ace.dmg" >/dev/null 2>&1 || say_fail "Ace.dmg could not be made."
  say_ok "Mac copy ready: Ace for the business/Ace.dmg"
fi

if [[ $WHAT == both || $WHAT == iphone ]]; then
  # The iPhones get Ace through TestFlight (decision Oct 24). The cable
  # install (install-iphone.sh) builds its own Ad Hoc copy when needed.
  "$SETUP_DIR/upload-testflight.sh" || exit 1
  # Kept for the cable install backup.
  rm -rf "$WORK/ios.xcarchive"; cp -R "$WORK/tf.xcarchive" "$WORK/ios.xcarchive"
fi
