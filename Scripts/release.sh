#!/bin/bash
# Prepares a release the app's updater can install, and with --publish puts it on GitHub.
# Usage: Scripts/release.sh [--publish] [--download-prefix <url>]
#
# Builds the disk image (Scripts/make-dmg.sh), signs it with the update key and writes the
# feed the app reads, appcast.xml, into build/release/v<version>/ beside the image. The feed
# names one release, this one: the app asks for the file attached to whichever release is the
# latest (see SUFeedURL in Resources/Info.plist).
#
# The update key is a file, not a keychain item: $ARANOTCH_UPDATE_KEY or
# ~/.aranotch/update-signing.key (made by Scripts/update/make-signing-key.swift). Keep a copy
# somewhere safe: installed copies of the app accept updates signed with this key only.
#
# Release notes: docs/releases/<version>.md when there is one, otherwise the subject of the
# last commit.
#
# --download-prefix: where the image will be fetched from, for trying an update from a
# folder on this Mac (file:///...) before anything is published.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${ARANOTCH_REPO:-truonggialong/ara-notch}"
KEY="${ARANOTCH_UPDATE_KEY:-$HOME/.aranotch/update-signing.key}"
PUBLISH=0
PREFIX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --publish) PUBLISH=1 ;;
        --download-prefix) PREFIX="$2"; shift ;;
        *) echo "usage: $0 [--publish] [--download-prefix <url>]" >&2; exit 64 ;;
    esac
    shift
done

TOOLS=".build/artifacts/sparkle/Sparkle/bin"
[[ -x "$TOOLS/generate_appcast" ]] || swift package resolve
[[ -f "$KEY" ]] || { echo "no update key at $KEY (see Scripts/update/make-signing-key.swift)" >&2; exit 1; }

Scripts/make-dmg.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
DMG="build/AraNotch-$VERSION.dmg"
OUT="build/release/$TAG"
[[ -n "$PREFIX" ]] || PREFIX="https://github.com/$REPO/releases/download/$TAG/"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$DMG" "$OUT/"
NOTES="$OUT/AraNotch-$VERSION.md"
if [[ -f "docs/releases/$VERSION.md" ]]; then
    cp "docs/releases/$VERSION.md" "$NOTES"
else
    git log -1 --pretty=%s > "$NOTES"
fi

"$TOOLS/generate_appcast" --ed-key-file "$KEY" --download-url-prefix "$PREFIX" --embed-release-notes \
    -o "$OUT/appcast.xml" "$OUT" >/dev/null
grep -q 'sparkle:edSignature=' "$OUT/appcast.xml" || { echo "the feed has no signature" >&2; exit 1; }
echo "Release $TAG ready in $OUT"

if [[ "$PUBLISH" == 1 ]]; then
    gh release create "$TAG" "$OUT/AraNotch-$VERSION.dmg" "$OUT/appcast.xml" --repo "$REPO" \
        --title "AraNotch $VERSION" --notes-file "$NOTES"
    echo "Published $TAG to https://github.com/$REPO/releases/tag/$TAG"
fi
