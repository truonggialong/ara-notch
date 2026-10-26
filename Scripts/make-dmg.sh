#!/bin/bash
# Builds a release of AraNotch and packs it into build/AraNotch-<version>.dmg.
# Usage: Scripts/make-dmg.sh
#
# The disk image holds AraNotch.app and a shortcut to /Applications, for the usual drag to install.
# The app is built for Apple Silicon only (the Command Line Tools cannot build both architectures).
#
# Signing: the same as Scripts/build-app.sh, so the "AraNotch Dev" certificate when the keychain
# has it. That is not an Apple Developer ID and the app is not notarized: on another Mac, macOS
# refuses the first launch until the owner allows it in System Settings > Privacy & Security
# ("Open Anyway").
set -euo pipefail
cd "$(dirname "$0")/.."

Scripts/build-app.sh release

APP="build/AraNotch.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/AraNotch-$VERSION.dmg"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/AraNotch.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
# Recent macOS has `diskutil image` and calls `hdiutil create` deprecated; older ones only have hdiutil.
if diskutil image create from --help >/dev/null 2>&1; then
    diskutil image create from --format UDZO --volumeName "AraNotch $VERSION" "$STAGING" "$DMG" >/dev/null
else
    hdiutil create -volname "AraNotch $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
fi

# The image must hold an app whose signature is intact.
codesign --verify --deep --strict "$APP"
# The image itself is signed too, with the app's certificate when the keychain has it, so a
# damaged or altered download shows. (It is not a Developer ID: Gatekeeper still asks once.)
IDENTITY="${ARANOTCH_SIGN_IDENTITY:-AraNotch Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier com.aranotch.app.dmg "$DMG"
    codesign --verify "$DMG"
fi
echo "Wrote $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"
