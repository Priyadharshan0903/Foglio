#!/usr/bin/env bash
# Assembles Foglio.app by hand — this is what replaces Xcode.
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
SWIFT_BUILD=(swift build)
# Some restricted macOS runners cannot create SwiftPM's nested sandbox.
# Opt in for those environments; ordinary local builds retain the default.
if [ "${FOGLIO_DISABLE_SWIFT_SANDBOX:-0}" = "1" ]; then
  SWIFT_BUILD+=(--disable-sandbox)
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Just the app product. Building everything drags in the FoglioTests target,
# whose `@testable import` fails under -c release, where testability is off.
"${SWIFT_BUILD[@]}" -c "$CONFIG" --product Foglio
"${SWIFT_BUILD[@]}" -c "$CONFIG" --product FoglioMCP

BIN="$("${SWIFT_BUILD[@]}" -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/Foglio.app"

# Refresh the known contents in place. macOS can protect signed application
# directories from removal even when their files are writable.
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/Foglio" "$APP/Contents/MacOS/Foglio"
cp "$BIN/FoglioMCP" "$APP/Contents/MacOS/FoglioMCP"

# SwiftPM emits resources as a .bundle next to the binary; fold its contents
# into Contents/Resources so Bundle.main can find them (fonts, etc).
# SwiftPM names it <package>_<target>.bundle. Copy it wholesale rather than
# flattening it: Bundle.module looks for the bundle itself, not loose files.
for res in "$BIN"/Foglio_*.bundle; do
  [ -d "$res" ] && cp -R "$res" "$APP/Contents/Resources/"
done

# Icon: refresh when its source changes; compiler cache lives in the build
# folder so restricted runners can generate the same resource locally.
if [ ! -f "$ROOT/build/Foglio.icns" ] || [ "$ROOT/scripts/make-icon.swift" -nt "$ROOT/build/Foglio.icns" ]; then
  mkdir -p "$ROOT/build/IconModuleCache"
  swift -module-cache-path "$ROOT/build/IconModuleCache" scripts/make-icon.swift >/dev/null
fi
[ -f "$ROOT/build/Foglio.icns" ] && cp "$ROOT/build/Foglio.icns" "$APP/Contents/Resources/Foglio.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Foglio</string>
  <key>CFBundleDisplayName</key>       <string>Foglio</string>
  <key>CFBundleExecutable</key>        <string>Foglio</string>
  <key>CFBundleIconFile</key>          <string>Foglio</string>
  <key>CFBundleIdentifier</key>        <string>com.priyadharshan.foglio</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.5.0</string>
  <key>CFBundleVersion</key>           <string>10</string>
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
codesign --force --sign - "$APP/Contents/MacOS/FoglioMCP" >/dev/null 2>&1
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "built $APP"
du -sh "$APP" | awk '{print "size: " $1}'
