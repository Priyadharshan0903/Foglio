#!/usr/bin/env bash
# Packages Foglio.app into a drag-to-install disk image.
# Usage: scripts/dmg.sh [debug|release]
#
# The "Applications" symlink points at ~/Applications, not /Applications.
# /Applications is group-writable by `admin` only, so on an account without
# admin rights dragging there prompts for a password that can't be given.
# ~/Applications needs no privileges, and Spotlight and Launchpad index it just
# the same.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/bundle.sh "$CONFIG"

APP="$ROOT/build/Foglio.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/Foglio-$VERSION.dmg"
STAGE="$ROOT/build/dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"

cp -R "$APP" "$STAGE/Foglio.app"
ln -s "$HOME/Applications" "$STAGE/Applications"

# UDZO is compressed and read-only, which is what a distributable image should
# be — and what makes the copy out of it atomic from the Finder's side.
hdiutil create \
  -volname "Foglio $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

echo "built $DMG"
du -sh "$DMG" | awk '{print "size: " $1}'
