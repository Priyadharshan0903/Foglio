#!/usr/bin/env bash
# Installs Foglio from the disk image into ~/Applications, replacing any
# copy already there. No admin rights required at any step.
# Usage: scripts/install.sh [path-to-dmg]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Applications"
BUNDLE_ID="com.priyadharshan.foglio"

DMG="${1:-}"
if [ -z "$DMG" ]; then
  # Newest image built, so `make install` after `make dmg` needs no argument.
  DMG="$(ls -t "$ROOT"/build/Foglio-*.dmg 2>/dev/null | head -1 || true)"
fi
[ -n "$DMG" ] && [ -f "$DMG" ] || { echo "no disk image found — run: make dmg" >&2; exit 1; }

# Quit any running copy first. Replacing the bundle under a live process leaves
# it running the old code with its resources deleted out from under it, and the
# app only writes pending note edits on quit.
if pgrep -f "Foglio.app/Contents/MacOS/Foglio" >/dev/null 2>&1; then
  echo "quitting the running copy…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -f "Foglio.app/Contents/MacOS/Foglio" >/dev/null 2>&1 || break
    sleep 0.25
  done
  # Only escalate if it ignored the polite request.
  pgrep -f "Foglio.app/Contents/MacOS/Foglio" >/dev/null 2>&1 && pkill -f "Foglio.app/Contents/MacOS/Foglio" || true
fi

MOUNT="$(mktemp -d /tmp/foglio-mount.XXXXXX)"
cleanup() { hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true; rmdir "$MOUNT" 2>/dev/null || true; }
trap cleanup EXIT

hdiutil attach "$DMG" -mountpoint "$MOUNT" -nobrowse -quiet

mkdir -p "$DEST"

# Stage beside the target, then swap. A straight `cp -R` over a live bundle
# leaves a half-written app if it fails partway; this way the old copy is only
# removed once the new one is fully on disk.
STAGED="$DEST/.Foglio.app.incoming"
rm -rf "$STAGED"
cp -R "$MOUNT/Foglio.app" "$STAGED"

rm -rf "$DEST/Foglio.app"
mv "$STAGED" "$DEST/Foglio.app"

# Copying through a disk image can leave the quarantine flag, which makes
# Gatekeeper refuse an ad-hoc-signed app. Clear it for this locally built one.
xattr -dr com.apple.quarantine "$DEST/Foglio.app" 2>/dev/null || true

echo "installed $DEST/Foglio.app"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Foglio.app/Contents/Info.plist" \
  | awk '{print "version: " $1}'
