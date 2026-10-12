#!/bin/zsh
# Build a self-contained .app bundle (no Xcode project needed).
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
swift build -c "$CONFIG"

APP=".build/SSH Config Manager.app"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/SSHConfigManager"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SSHConfigManager"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SSH Config Manager</string>
    <key>CFBundleDisplayName</key><string>SSH Config Manager</string>
    <key>CFBundleExecutable</key><string>SSHConfigManager</string>
    <key>CFBundleIdentifier</key><string>com.local.sshconfigmanager</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "Built: $APP"
echo "Run:   open \"$APP\""
