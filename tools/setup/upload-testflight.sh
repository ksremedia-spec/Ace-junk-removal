#!/bin/zsh
# Builds the business iPhone copy of Ace and uploads it to TestFlight, where
# Ashley's and Alex's phones get it over the air (decision Oct 24).
# A TestFlight copy stops opening 90 days after upload, so this runs again
# every 60 days (testflight-job.sh) and by hand after any change.
# Usage: upload-testflight.sh                 the project as it is now
#        upload-testflight.sh --from-commit   the last committed version
#                                             (the automatic job uses this, so
#                                             half-done work never ships)
source "${0:A:h}/common.sh"
WORK="$HOME/Library/Caches/AceSetup"; mkdir -p "$WORK"
SRC="$REPO"
if [[ $1 == --from-commit ]]; then
  SRC="$WORK/commit-copy"
  rm -rf "$SRC"; git -C "$REPO" worktree prune
  git -C "$REPO" worktree add --detach "$SRC" HEAD >/dev/null 2>&1 || say_fail "Couldn't copy the last committed version."
  cp "$REPO/Ace/Support/SyncServer.txt" "$SRC/Ace/Support/SyncServer.txt" 2>/dev/null
fi
cd "$SRC" || say_fail "No project."
test -s Ace/Support/SyncServer.txt || say_fail "Ace/Support/SyncServer.txt is missing. Do step 2 first."
grep -q 'static let isBeta = false' Ace/Support/Beta.swift || say_fail "Beta mode is on in Ace/Support/Beta.swift."
# Each upload needs a higher build number: the date and time do that.
BUILD=$(date +%Y%m%d%H%M)

say_step "Building the iPhone copy (build $BUILD)"
rm -rf "$WORK/tf.xcarchive"
xcodebuild archive -project Ace.xcodeproj -scheme Ace -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$WORK/tf.xcarchive" -allowProvisioningUpdates CURRENT_PROJECT_VERSION=$BUILD \
  > "$WORK/tf-archive.log" 2>&1 || say_fail "The iPhone build failed (see $WORK/tf-archive.log)."
APP="$WORK/tf.xcarchive/Products/Applications/Ace.app"
find "$APP" -name BetaRelay.txt | grep -q . && say_fail "The copy still has the beta relay inside."
find "$APP" -name SyncServer.txt | grep -q . || say_fail "The copy has no server address inside."
say_ok "iPhone copy built"

say_step "Uploading it to TestFlight"
cat > "$WORK/tf-export.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>6YCK9MG5RD</string>
<key>testFlightInternalTestingOnly</key><true/>
<key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
rm -rf "$WORK/tf-export"
if ! xcodebuild -exportArchive -archivePath "$WORK/tf.xcarchive" -exportOptionsPlist "$WORK/tf-export.plist" \
    -exportPath "$WORK/tf-export" -allowProvisioningUpdates > "$WORK/tf-export.log" 2>&1; then
  grep -qi "no suitable application records\|app record\|Could not find an app" "$WORK/tf-export.log" \
    && say_fail "Apple has no app record for Ace yet. In App Store Connect: Apps › + › New App (bundle ID com.acejunkremoval.app), then try again."
  say_fail "Apple didn't take the upload (see $WORK/tf-export.log)."
fi
date +%s > "$WORK/last-testflight.txt"
say_ok "Uploaded build $BUILD. Apple takes about 15–30 minutes to process it; then it shows in TestFlight on their phones."
[[ $1 == --from-commit ]] && git -C "$REPO" worktree remove --force "$SRC" >/dev/null 2>&1
exit 0
