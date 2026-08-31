#!/usr/bin/env bash
# Assembles Foglio.app by hand — this is what replaces Xcode.
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/Foglio.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Foglio" "$APP/Contents/MacOS/Foglio"

# SwiftPM emits resources as a .bundle next to the binary; fold its contents
# into Contents/Resources so Bundle.main can find them (fonts, etc).
if [ -d "$BIN/Foglio_Foglio.bundle" ]; then
  cp -R "$BIN/Foglio_Foglio.bundle/." "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Foglio</string>
  <key>CFBundleDisplayName</key>       <string>Foglio</string>
  <key>CFBundleExecutable</key>        <string>Foglio</string>
  <key>CFBundleIdentifier</key>        <string>com.priyadharshan.foglio</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key>           <string>1</string>
  <key>LSMinimumSystemVersion</key>    <string>14.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>ATSApplicationFontsPath</key>   <string>Fonts</string>

  <!-- EventKit refuses to prompt (and the app traps) without these. -->
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Foglio shows today's meetings beside your notes and tasks. Your calendar data stays on this Mac.</string>
  <key>NSCalendarsUsageDescription</key>
  <string>Foglio shows today's meetings beside your notes and tasks. Your calendar data stays on this Mac.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature — enough to run locally. A real identity is only needed once
# we ship or once EventKit's permission prompt comes into play.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"

echo "built $APP"
du -sh "$APP" | awk '{print "size: " $1}'
