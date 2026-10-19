#!/bin/zsh
# Builds NIZ Config.app (and nizctl) into ./dist.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --product NIZConfig
swift build -c release --product nizctl
BIN=$(swift build -c release --show-bin-path)

APP="dist/NIZ Config.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/NIZConfig" "$APP/Contents/MacOS/NIZConfig"
cp "$BIN/nizctl" dist/nizctl

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>NIZ Config</string>
    <key>CFBundleDisplayName</key><string>NIZ Config</string>
    <key>CFBundleIdentifier</key><string>local.niz.config</string>
    <key>CFBundleExecutable</key><string>NIZConfig</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP and dist/nizctl"
