#!/bin/bash
# Cut a Fog release: build at a version, zip the .app, publish to GitHub Releases.
#
#   FOG_REPO=youruser/fog ./release.sh 1.1
#
# Requires: gh CLI authenticated (gh auth login) and the repo to exist.
set -euo pipefail
cd "$(dirname "$0")"

VER="${1:?usage: ./release.sh <version>   e.g. ./release.sh 1.1}"
REPO="${FOG_REPO:-padakan/fog}"

echo "→ Building Fog $VER (repo $REPO)"
VERSION="$VER" FOG_REPO="$REPO" ./build.sh

ZIP="dist/Fog-${VER}.zip"
echo "→ Zipping → $ZIP (for the in-app self-updater)"
rm -f "$ZIP"
# keepParent so the archive contains Fog.app at its root
ditto -c -k --sequesterRsrc --keepParent "dist/Fog.app" "$ZIP"

echo "→ Building DMG (for first-time install)"
VERSION="$VER" ./dmg.sh "$VER"
# Stable filename so the site/README link straight to the latest DMG:
#   https://github.com/OWNER/REPO/releases/latest/download/Fog.dmg
cp "dist/Fog-${VER}.dmg" "dist/Fog.dmg"
DMG="dist/Fog.dmg"

echo "→ Publishing v$VER to GitHub Releases"
gh release create "v$VER" "$DMG" "$ZIP" \
    --repo "$REPO" \
    --title "Fog $VER" \
    --notes "Download **Fog.dmg**, drag Fog into Applications. First launch: right-click → Open." \
    --latest

echo "✓ Released v$VER — Fog.dmg (install) + ZIP (auto-update) attached."
