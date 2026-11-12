#!/bin/bash
# Build a release binary and bundle it into BrewDesktop.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/BrewDesktop.app"
CONTENTS="$APP/Contents"
BIN=".build/release/BrewDesktop"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN" "$CONTENTS/MacOS/BrewDesktop"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>BrewDesktop</string>
    <key>CFBundleDisplayName</key>
    <string>BrewDesktop</string>
    <key>CFBundleIdentifier</key>
    <string>io.brewdesktop.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>BrewDesktop</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "Built: $(pwd)/$APP"
