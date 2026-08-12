#!/bin/bash
# Builds the public release artifact: a UNIVERSAL (arm64 + x86_64) Burndown.app, ad-hoc signed,
# zipped with a checksum, in dist/. Never touches the dev bundle Burndown.app/ (so the running
# app, its TCC grants, and the LaunchAgent are unaffected).
#
# Signing note: releases are ad-hoc signed until a Developer ID certificate exists. macOS
# Gatekeeper will block the first open of a downloaded copy; README's Install section documents
# the four ways past it (Homebrew with HOMEBREW_CASK_OPTS, xattr -d, System Settings > Open
# Anyway, or building from source).
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(sed -n 's/^let kAppVersion = "\([^"]*\)".*/\1/p' Sources/Settings.swift)"
# NO fallback. This used to default to 1.0, which is worse than any failure it was covering: 1.0
# is from the abandoned 1.x scheme AND it sorts above every real version, so a build stamped with
# it would report a version that never existed and could never be superseded by a 0.9.x release.
# The updater would go quiet forever. If the version cannot be read, that is a broken build, and a
# broken build should stop rather than invent a number.
[ -n "$VERSION" ] || { echo "ABORT: could not read kAppVersion from Sources/Settings.swift"; exit 1; }
DIST="dist"
APP="$DIST/Burndown.app"
FRAMEWORKS="-framework AppKit -framework SwiftUI -framework Combine -framework Charts -framework UserNotifications -framework ServiceManagement"

echo "→ Release build $VERSION (universal)"
rm -rf "$DIST"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
    echo "→ Compiling $ARCH slice"
    swiftc -O -target "$ARCH-apple-macos13.0" $FRAMEWORKS \
        -o "$DIST/Burndown-$ARCH" Sources/*.swift
done
lipo -create "$DIST/Burndown-arm64" "$DIST/Burndown-x86_64" -output "$APP/Contents/MacOS/Burndown"
rm "$DIST/Burndown-arm64" "$DIST/Burndown-x86_64"
lipo -info "$APP/Contents/MacOS/Burndown"

echo "→ Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Burndown</string>
    <key>CFBundleDisplayName</key>     <string>Burndown</string>
    <key>CFBundleIdentifier</key>      <string>com.maz.burndown</string>
    <key>CFBundleVersion</key>         <string>$VERSION</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Burndown</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "→ Resources"
if [ -f Icon/AppIcon-1024.png ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
        sips -z $s $s Icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2)); sips -z $d $d Icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    cp Icon/AppIcon-1024.png "$ICONSET/icon_512x512@2x.png"
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
cp Sounds/*.wav "$APP/Contents/Resources/"
cp docs/RELEASE_NOTES.md docs/PRIVACY.md "$APP/Contents/Resources/"

echo "→ Ad-hoc signing"
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - --identifier com.maz.burndown "$APP"
codesign -v "$APP" && echo "  signature valid"

echo "→ Packaging"
ZIP="$DIST/Burndown-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "✓ Release artifact: $ZIP"
