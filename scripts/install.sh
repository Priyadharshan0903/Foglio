#!/usr/bin/env bash
# Installs Foglio into ~/Applications from a DMG or a local app bundle.
# The previous app is kept beside the incoming copy for rollback.
# Usage: scripts/install.sh [path-to-dmg-or-app]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/Applications"
TARGET="$DEST/Foglio.app"
SOURCE="${1:-}"

if [ -z "$SOURCE" ]; then
  SOURCE="$(ls -t "$ROOT"/build/Foglio-*.dmg 2>/dev/null | head -1 || true)"
  # A newer local bundle should not be replaced by an older leftover DMG.
  BUILT_PLIST="$ROOT/build/Foglio.app/Contents/Info.plist"
  if [ -f "$BUILT_PLIST" ] && { [ -z "$SOURCE" ] || [ "$BUILT_PLIST" -nt "$SOURCE" ]; }; then
    SOURCE="$ROOT/build/Foglio.app"
  fi
fi
[ -n "$SOURCE" ] && [ -e "$SOURCE" ] || { echo "no installation source found — run: make dmg" >&2; exit 1; }

MOUNT=""
STAGING=""
cleanup() {
  if [ -n "$MOUNT" ]; then
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT" 2>/dev/null || true
  fi
  # A backup or interrupted incoming copy is intentionally retained.
  if [ -n "$STAGING" ]; then rmdir "$STAGING" 2>/dev/null || true; fi
}
trap cleanup EXIT

case "$SOURCE" in
  *.app) APP_SOURCE="$SOURCE" ;;
  *.dmg)
    MOUNT="$(mktemp -d /tmp/foglio-mount.XXXXXX)"
    hdiutil attach "$SOURCE" -mountpoint "$MOUNT" -nobrowse -quiet
    APP_SOURCE="$MOUNT/Foglio.app"
    ;;
  *) echo "expected a Foglio .dmg or .app" >&2; exit 1 ;;
esac

# Validate and stage before asking the old application to close.
codesign --verify --deep --strict "$APP_SOURCE"
mkdir -p "$DEST"
STAGING="$(mktemp -d "$DEST/.foglio-install.XXXXXX")"
ditto "$APP_SOURCE" "$STAGING/Foglio.app"
codesign --verify --deep --strict "$STAGING/Foglio.app"

# Checking by path works even if Launch Services has not indexed the bundle
# identifier. Do not force-kill: quitting lets Foglio flush pending note edits.
if [ -d "$TARGET" ]; then
  RUNNING="$(osascript -e "application \"$TARGET\" is running")"
  if [ "$RUNNING" = "true" ]; then
    echo "quitting the running copy…"
    osascript -e "tell application \"$TARGET\" to quit"
    for _ in $(seq 1 20); do
      RUNNING="$(osascript -e "application \"$TARGET\" is running")"
      [ "$RUNNING" = "true" ] || break
      sleep 0.25
    done
    [ "$RUNNING" = "false" ] || { echo "Foglio is still running; close it and retry." >&2; exit 1; }
  fi
  mv "$TARGET" "$STAGING/Previous.app"
fi

if ! mv "$STAGING/Foglio.app" "$TARGET"; then
  if [ -d "$STAGING/Previous.app" ]; then mv "$STAGING/Previous.app" "$TARGET"; fi
  echo "installation failed; the previous application was restored" >&2
  exit 1
fi

# This is a locally built, ad-hoc-signed app.
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true
codesign --verify --deep --strict "$TARGET"
echo "installed $TARGET"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist" \
  | awk '{print "version: " $1}'
if [ -d "$STAGING/Previous.app" ]; then echo "backup: $STAGING/Previous.app"; fi
