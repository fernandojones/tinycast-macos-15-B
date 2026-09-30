#!/bin/bash
set -euo pipefail

ROOT=`cd \`dirname "$0"\` && pwd`
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

IDENTITY="${CODESIGN_IDENTITY:-Tinycast Self-Signed}"
DERIVED="build/DerivedData"

if [ "$IDENTITY" != "-" ]; then
    if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
        echo "✗ '$IDENTITY' code-signing identity not found — create it once (docs/signing.md)." >&2
        exit 1
    fi
fi

echo "▸ Building signed Tinycast.app (Release)…"
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/Tinycast.app"
VERSION=`/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"`
DMG="build/Tinycast-${VERSION}.dmg"

echo "▸ Packaging ${DMG}"
STAGE=`mktemp -d`
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "Tinycast" "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✓ $DMG"