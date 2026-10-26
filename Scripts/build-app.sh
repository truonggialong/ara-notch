#!/bin/bash
# Builds build/AraNotch.app. Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
if [[ "$CONFIG" != "debug" && "$CONFIG" != "release" ]]; then
    echo "usage: $0 [debug|release]" >&2
    exit 64
fi

swift build -c "$CONFIG" --product AraNotch
swift build -c "$CONFIG" --product aranotch-mcp
swift build -c "$CONFIG" --product aranotch-hook
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/AraNotch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/AraNotch" "$APP/Contents/MacOS/AraNotch"
# The helper AI agents run to read the clipboard history (see the Clipboard settings tab).
cp "$BIN_DIR/aranotch-mcp" "$APP/Contents/MacOS/aranotch-mcp"
# The helper Claude Code runs as a hook to report its sessions (see the Agents settings tab).
cp "$BIN_DIR/aranotch-hook" "$APP/Contents/MacOS/aranotch-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# What the app does with privacy-sensitive interfaces: no tracking, nothing collected.
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

# The app's own licence (GPL-3.0) and the notices of the software it includes. The notices name
# the Sparkle version in Package.resolved: a new Sparkle needs its licence copied in again.
SPARKLE_VERSION="$(/usr/bin/python3 -c 'import json,sys; print(next(p["state"]["version"] for p in json.load(sys.stdin)["pins"] if p["identity"] == "sparkle"))' < Package.resolved)"
if ! grep -q "^Sparkle $SPARKLE_VERSION " Resources/ThirdPartyNotices.txt; then
    echo "Resources/ThirdPartyNotices.txt does not name Sparkle $SPARKLE_VERSION: copy its LICENSE in again" >&2
    exit 1
fi
# Both open from the About page, so they end in .txt.
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/ThirdPartyNotices.txt"

# The updater (Sparkle) is a framework inside the app; the program finds it there.
mkdir -p "$APP/Contents/Frameworks"
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/AraNotch" 2>/dev/null

# Signing. With a code signing certificate named "AraNotch Dev" in the keychain (or the name in
# ARANOTCH_SIGN_IDENTITY), the app keeps the same identity across builds, so macOS keeps its
# Accessibility and other permissions. Without one the signature is ad-hoc: fine for running,
# but every build is a new app to macOS and permissions must be granted again.
# Distribution needs a Developer ID.
IDENTITY="${ARANOTCH_SIGN_IDENTITY:-AraNotch Dev}"
sign_with_identity() {
    # Listed even when the certificate is self-signed and not marked as trusted.
    security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\"" || return 1
    sign_all "$IDENTITY"
}
# Inside out: the updater's helpers, then the framework, the app's own helpers, and the app.
# An update is only installed over an app signed by the same hand, helpers included.
sign_all() {
    local sparkle="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
    codesign --force --sign "$1" "$sparkle/XPCServices/Installer.xpc" \
        && codesign --force --sign "$1" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc" \
        && codesign --force --sign "$1" "$sparkle/Autoupdate" \
        && codesign --force --sign "$1" "$sparkle/Updater.app" \
        && codesign --force --sign "$1" "$APP/Contents/Frameworks/Sparkle.framework" \
        && codesign --force --sign "$1" "$APP/Contents/MacOS/aranotch-mcp" "$APP/Contents/MacOS/aranotch-hook" \
        && codesign --force --sign "$1" "$APP"
}
if sign_with_identity; then
    echo "Built $APP ($CONFIG, signed as $IDENTITY)"
else
    sign_all -
    echo "Built $APP ($CONFIG, ad-hoc signature: no usable \"$IDENTITY\" certificate)"
fi
