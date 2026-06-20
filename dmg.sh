#!/bin/bash
# Package dist/Fog.app into a styled drag-to-install .dmg.
#
#   ./dmg.sh            # uses VERSION (default 1.0)
#   ./dmg.sh 1.1
#
# Produces dist/Fog-<version>.dmg: a window with a background + arrow, Fog.app on the
# left and an Applications shortcut on the right. Run ./build.sh first.
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:-${VERSION:-1.0}}"
APP="dist/Fog.app"
BG="Resources/dmg-background.png"
VOL="Fog"
DMG="dist/Fog-${VER}.dmg"

[ -d "$APP" ] || { echo "✗ $APP not found — run ./build.sh first"; exit 1; }

STAGE="$(mktemp -d)/stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Fog.app"
ln -s /Applications "$STAGE/Applications"
[ -f "$BG" ] && cp "$BG" "$STAGE/.background/bg.png"

# Read-write DMG we can lay out, then compress.
RW="$(mktemp -d)/rw.dmg"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
DEV="$(hdiutil attach "$RW" -nobrowse -noautoopen | egrep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOL"
sleep 1

if [ -f "$BG" ]; then
  osascript <<EOF 2>/dev/null || echo "  (Finder layout skipped — automation not permitted; DMG still works)"
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:bg.png"
    set position of item "Fog.app" of container window to {150, 205}
    set position of item "Applications" of container window to {450, 205}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
fi

sync
hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$MOUNT" >/dev/null 2>&1 || true

rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$(dirname "$STAGE")" "$(dirname "$RW")"

echo "✓ Built $DMG"
