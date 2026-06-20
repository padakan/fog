#!/bin/bash
# Build ClaudeStatusBorder into a proper .app bundle (needed for notifications).
set -euo pipefail

cd "$(dirname "$0")"

EXE_NAME="ClaudeStatusBorder"          # Swift target / binary name
APP_DISPLAY="Fog"                      # user-facing app name
BUNDLE_ID="com.padagot.fog"
VERSION="${VERSION:-1.0}"              # override: VERSION=1.1 ./build.sh
UPDATE_REPO="${FOG_REPO:-padakan/fog}"   # GitHub "owner/repo" used for self-update
DIST="dist"
APP="${DIST}/${APP_DISPLAY}.app"

echo "→ swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${EXE_NAME}"

echo "→ assembling ${APP}"
rm -rf "${DIST}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"
cp "$BIN_PATH" "${APP}/Contents/MacOS/${EXE_NAME}"

# Bundle sound assets if present.
if compgen -G "Resources/*.mp3" > /dev/null; then
    cp Resources/*.mp3 "${APP}/Contents/Resources/"
fi

# Bundle the menu-bar template icon.
if [ -f "Resources/MenuBarIcon.svg" ]; then
    cp Resources/MenuBarIcon.svg "${APP}/Contents/Resources/"
fi

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_DISPLAY}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_DISPLAY}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${EXE_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>FogUpdateRepo</key>
    <string>${UPDATE_REPO}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string></string>
</dict>
</plist>
PLIST

# Generate the app icon (.icns) from a 1024×1024 source if present.
ICON_SRC="Resources/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
                "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
                "512:512x512" "1024:512x512@2x"; do
        px="${spec%%:*}"; name="${spec##*:}"
        sips -z "$px" "$px" "$ICON_SRC" --out "${ICONSET}/icon_${name}.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "${APP}/Contents/Resources/AppIcon.icns" && echo "✓ App icon generated"
    rm -rf "$(dirname "$ICONSET")"
fi

# Ad-hoc sign so the app has a stable identity for notification permissions.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Built ${APP}"
echo "  Run it with:  open \"${APP}\""
