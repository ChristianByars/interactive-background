#!/usr/bin/env bash
# Builds "Interactive Background.app" into build/. Usage: scripts/make-app.sh (any cwd)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Interactive Background.app"

cd "$ROOT/src"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/InteractiveBackground" "$APP/Contents/MacOS/InteractiveBackground"
# Resources live in Contents/Resources (found via Bundle.main), not SwiftPM's *_WallpaperEngine.bundle:
# the .app must not depend on Bundle.module or the .build directory.
cp -R "$ROOT/src/Sources/WallpaperEngine/Resources/Wallpapers" "$APP/Contents/Resources/Wallpapers"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Interactive Background</string>
    <key>CFBundleIdentifier</key><string>com.christianbyars.InteractiveBackground</string>
    <key>CFBundleExecutable</key><string>InteractiveBackground</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run on this Mac. Distribution later needs a Developer ID + notarization.
codesign --force --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"
echo "Built: $APP"
