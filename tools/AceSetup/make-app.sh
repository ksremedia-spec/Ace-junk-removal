#!/bin/zsh
# Builds "Ace Setup.app" onto the Desktop.
set -e
cd "${0:A:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$HOME/Desktop/Xcode 2.app/Contents/Developer}"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | tail -3
APP="$HOME/Desktop/Ace Setup.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/AceSetup "$APP/Contents/MacOS/AceSetup"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AceSetup</string>
<key>CFBundleIdentifier</key><string>com.acejunkremoval.setup</string>
<key>CFBundleName</key><string>Ace Setup</string>
<key>CFBundleDisplayName</key><string>Ace Setup</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>AceRepo</key><string>${PWD:h:h}</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built: $APP"
