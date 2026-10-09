#!/bin/bash
#
# Builds a GoldenIce release: GoldenIce.app signed with Developer ID and notarized, as a zip
# and a DMG. Nothing is uploaded. See docs/RELEASING.md.
#
# Usage: Scripts/release.sh [--skip-notarize] [--appcast]
#
# Machine-specific settings live in Scripts/release.local.env, which git ignores, so that
# nothing about the signing identity or notarization credentials ends up in the repository:
#
#     NOTARY_PROFILE=<name of a `xcrun notarytool store-credentials` keychain profile>
#
# The Developer ID certificate is found in the keychain; its team is never written down.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_CONFIG="$ROOT/Scripts/release.local.env"
# shellcheck disable=SC1090
[ -f "$LOCAL_CONFIG" ] && source "$LOCAL_CONFIG"

DERIVED="${DERIVED:-/tmp/goldenice-release}"
OUT="${OUT:-$ROOT/build/releases}"
NOTARIZE=1
APPCAST=0
for ARG in "$@"; do
    case "$ARG" in
        --skip-notarize) NOTARIZE=0 ;;
        --appcast) APPCAST=1 ;;
        *) echo "error: unknown option $ARG" >&2; exit 1 ;;
    esac
done
if [ "$NOTARIZE" = 1 ] && [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "error: set NOTARY_PROFILE in Scripts/release.local.env, or pass --skip-notarize" >&2
    exit 1
fi

TEAM="$(security find-certificate -c "Developer ID Application" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
[ -n "$TEAM" ] || { echo "error: no Developer ID Application certificate in the keychain" >&2; exit 1; }

echo "==> Building Release, signed with Developer ID"
xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES \
    | tail -1

APP="$DERIVED/Build/Products/Release/GoldenIce.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
mkdir -p "$OUT"
ZIP="$OUT/GoldenIce-$VERSION.zip"
DMG="$OUT/GoldenIce-$VERSION.dmg"
rm -f "$ZIP" "$DMG"

echo "==> Verifying the signature"
codesign --verify --deep --strict "$APP"

if [ "$NOTARIZE" = 1 ]; then
    echo "==> Notarizing the app"
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    rm -f "$OUT/notarize.zip"
    xcrun stapler staple "$APP"
fi

echo "==> Packaging"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGING="$(mktemp -d)"
ditto "$APP" "$STAGING/GoldenIce.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "GoldenIce $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [ "$NOTARIZE" = 1 ]; then
    echo "==> Notarizing the DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | sed 's/^/    /'
    spctl -a -vv "$APP" 2>&1 | sed 's/^/    /'
fi

if [ "$APPCAST" = 1 ]; then
    SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts" -path '*Sparkle/bin' -type d | head -1)"
    echo "==> Generating the appcast"
    "$SPARKLE_BIN/generate_appcast" \
        --download-url-prefix "https://github.com/scoopy115/GoldenIce/releases/download/v$VERSION/" \
        -o "$OUT/appcast.xml" "$OUT"
fi

echo
echo "Built GoldenIce $VERSION ($BUILD) in $OUT"
ls -1 "$OUT" | sed 's/^/  /'
