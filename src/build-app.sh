#!/usr/bin/env bash
# Builds "Wallpaper Spike.app" into src/build/. Usage: ./build-app.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Wallpaper Spike.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/WallpaperSpike"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/WallpaperSpike"
cp -R ../wallpapers/aurora "$APP/Contents/Resources/aurora"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Wallpaper Spike</string>
    <key>CFBundleDisplayName</key><string>Wallpaper Spike</string>
    <key>CFBundleIdentifier</key><string>com.christianbyars.wallpaperspike</string>
    <key>CFBundleExecutable</key><string>WallpaperSpike</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac. Distribution later needs a Developer ID + notarization.
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"
