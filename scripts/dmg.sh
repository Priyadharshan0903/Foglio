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
STAGE="$(mktemp -d "$ROOT/build/.foglio-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGE" 2>/dev/null || true; }
trap cleanup EXIT

codesign --verify --deep --strict "$APP"
CONTENTS="$STAGE/contents"
mkdir -p "$CONTENTS"
ditto "$APP" "$CONTENTS/Foglio.app"
ln -s "$HOME/Applications" "$CONTENTS/Applications"

# UDZO is compressed and read-only, which is what a distributable image should
# be — and what makes the copy out of it atomic from the Finder's side.
if ! hdiutil create \
  -volname "Foglio $VERSION" \
  -srcfolder "$CONTENTS" \
  -ov -format UDZO \
  "$DMG" >/dev/null; then
  # Some build environments cannot attach the temporary device used by create.
  # Generate the HFS+ filesystem in a file, then compress it without mounting.
  echo "trying HFS+ image packaging…"
  hdiutil makehybrid -hfs -hfs-volume-name "Foglio $VERSION" \
    -o "$STAGE/Foglio-hybrid.dmg" "$CONTENTS" >/dev/null
  hdiutil convert "$STAGE/Foglio-hybrid.dmg" -format UDZO -ov \
    -o "$DMG" >/dev/null
fi

hdiutil verify "$DMG" >/dev/null

echo "built $DMG"
du -sh "$DMG" | awk '{print "size: " $1}'
