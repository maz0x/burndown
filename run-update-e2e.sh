#!/bin/bash
# End-to-end proof that auto-update works: builds a deliberately OLD (0.0.1) copy of the current
# sources into a throwaway bundle outside the source tree, runs it with CUB_UPDATE_NOW=1, and
# lets it do the real thing: query GitHub, download the published release, verify the SHA-256,
# verify the signature, swap itself in place, and relaunch.
#
# Verifies afterwards that the throwaway bundle really became the published version. Touches
# nothing in this repo and nothing the user is running.
set -uo pipefail
cd "$(dirname "$0")"

WORK="${TMPDIR:-/tmp}/burndown-e2e"
APP="$WORK/Burndown.app"
SRC="$WORK/src"
rm -rf "$WORK"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SRC"

# The fake "old" version the throwaway bundle claims to be. It must be strictly LOWER than the
# published release, or the updater correctly offers nothing and this test fails for the wrong
# reason. That is exactly what happened when this was hardcoded to 0.9 and the release became
# v0.9.0: the comparison is numeric, so 0.9 and 0.9.0 are the SAME version and no update is due.
# Keep it at a version below any real release, and assert that rather than trusting it.
OLDVER="${OLDVER:-0.0.1}"   # override to test a specific upgrade path, e.g. OLDVER=0.9.0 ./run-update-e2e.sh
CURVER="$(sed -n 's/^let kAppVersion = "\([^"]*\)".*/\1/p' Sources/Settings.swift)"
if [ "$(printf '%s\n%s\n' "$OLDVER" "$CURVER" | sort -V | head -1)" != "$OLDVER" ] || [ "$OLDVER" = "$CURVER" ]; then
    echo "FAIL: test setup is broken. OLDVER ($OLDVER) must be strictly older than the current"
    echo "      version ($CURVER), otherwise no update is due and this test proves nothing."
    exit 1
fi

echo "→ Building a $OLDVER test build (current code, old version number)"
cp Sources/*.swift "$SRC/"
sed -i '' "s/^let kAppVersion = \"[^\"]*\"/let kAppVersion = \"$OLDVER\"/" "$SRC/Settings.swift"
swiftc -O -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework Combine -framework Charts \
  -framework UserNotifications -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Burndown" "$SRC"/*.swift || { echo "FAIL: test build did not compile"; exit 1; }

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Burndown</string>
    <key>CFBundleIdentifier</key>      <string>com.maz.burndown</string>
    <key>CFBundleVersion</key>         <string>$OLDVER</string>
    <key>CFBundleShortVersionString</key> <string>$OLDVER</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Burndown</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
</dict>
</plist>
PLIST
cp Sounds/*.wav "$APP/Contents/Resources/" 2>/dev/null
codesign --force --sign - --identifier com.maz.burndown "$APP" 2>/dev/null

echo "→ Running the real check + install (network)"
LOG="$WORK/e2e.log"
# A throwaway defaults suite keeps the test out of the user's real settings.
CUB_UPDATE_NOW=1 "$APP/Contents/MacOS/Burndown" > "$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 120); do
    kill -0 $PID 2>/dev/null || break
    grep -q "readyToRelaunch\|failed" "$LOG" 2>/dev/null && sleep 2 && break
    sleep 1
done
sleep 3
kill -9 $PID 2>/dev/null
# The installer relaunches the updated copy; stop it so no stray icon is left behind.
pkill -f "$APP/Contents/MacOS/Burndown" 2>/dev/null

echo "── state trace ──"; sed 's/^/   /' "$LOG"; echo "─────────────────"

INSTALLED="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"
EXPECTED="$(sed -n 's/^let kAppVersion = "\([^"]*\)".*/\1/p' Sources/Settings.swift)"

if grep -q "failed" "$LOG"; then echo "FAIL: updater reported a failure"; exit 1; fi
if [ "$INSTALLED" = "$EXPECTED" ]; then
    echo "✓ E2E PASS: the $OLDVER build updated itself to $INSTALLED in place"
    exit 0
else
    echo "FAIL: bundle is at '$INSTALLED', expected '$EXPECTED'"
    exit 1
fi
