#!/bin/bash
#
# Builds a GoldenIce release: GoldenIce.app signed with Developer ID and notarized, as a zip
# and a DMG. Nothing is uploaded. See docs/RELEASING.md.
#
# Usage: Scripts/release.sh [--skip-notarize] [--appcast]
#
# --appcast signs the DMG with GoldenIce's update key and writes build/releases/appcast.xml,
# which installed copies read to find the update.
#
# Machine-specific settings live in Scripts/release.local.env, which git ignores, so that
# nothing about the signing identity or notarization credentials ends up in the repository:
#
#     NOTARY_PROFILE=<name of a `xcrun notarytool store-credentials` keychain profile>
#
# The Developer ID certificate is found in the keychain; its team is never written down.
#
# GitHub Actions (.github/workflows/release.yml) runs the same script with its credentials in the
# environment instead, taken from the repository's encrypted secrets:
#
#     NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   an App Store Connect API key, or
#     APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID     an Apple ID with an app-specific password
#     SPARKLE_KEY_FILE                                the update key, exported by generate_keys -x
#     MARKETING_VERSION, BUILD_NUMBER                 the version to build, instead of the project's
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
# How notarytool signs in: a keychain profile on a Mac, credentials from the environment on CI.
if [ -n "${NOTARY_PROFILE:-}" ]; then
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER:-}" ]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    NOTARY_AUTH=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
elif [ "$NOTARIZE" = 1 ]; then
    echo "error: set NOTARY_PROFILE in Scripts/release.local.env, or pass --skip-notarize" >&2
    exit 1
fi

# A version given from outside replaces the project's, so CI can number releases itself.
VERSION_OVERRIDES=()
[ -n "${MARKETING_VERSION:-}" ] && VERSION_OVERRIDES+=(MARKETING_VERSION="$MARKETING_VERSION")
[ -n "${BUILD_NUMBER:-}" ] && VERSION_OVERRIDES+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

TEAM="$(security find-certificate -c "Developer ID Application" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
[ -n "$TEAM" ] || { echo "error: no Developer ID Application certificate in the keychain" >&2; exit 1; }

echo "==> Building Release, signed with Developer ID"
xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ${VERSION_OVERRIDES[@]+"${VERSION_OVERRIDES[@]}"} \
    | tail -1

APP="$DERIVED/Build/Products/Release/GoldenIce.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
mkdir -p "$OUT"
ZIP="$OUT/GoldenIce-$VERSION.zip"
DMG="$OUT/GoldenIce-$VERSION.dmg"
rm -f "$ZIP" "$DMG"

# Xcode signs Sparkle's framework but leaves the helpers inside it with Sparkle's own signature,
# which notarization refuses. Sign them again, inside out, as Sparkle's documentation says, then
# the app's own service and the app, so every seal covers what is now inside it.
echo "==> Signing Sparkle's helpers and the app with Developer ID"
SIGN=(codesign --force --sign "Developer ID Application" --options runtime --timestamp)
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
"${SIGN[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
"${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
"${SIGN[@]}" "$SPARKLE/Versions/B/Autoupdate"
"${SIGN[@]}" "$SPARKLE/Versions/B/Updater.app"
"${SIGN[@]}" "$SPARKLE"
"${SIGN[@]}" "$APP/Contents/XPCServices/MenuBarItemService.xpc"
"${SIGN[@]}" "$APP"

echo "==> Verifying the signature"
codesign --verify --deep --strict "$APP"
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q get-task-allow; then
    echo "error: the app still carries the get-task-allow entitlement" >&2
    exit 1
fi

# Submits a file for notarization and stops the script, with Apple's log, unless it is accepted.
notarize() {
    local RESULT
    RESULT="$(xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait 2>&1)"
    echo "$RESULT" | grep -E "id:|status:" | sort -u | sed 's/^/    /'
    if ! echo "$RESULT" | grep -q "status: Accepted"; then
        local ID
        ID="$(echo "$RESULT" | sed -n 's/.*id: \([0-9a-f-]*\).*/\1/p' | head -1)"
        echo "error: notarization was not accepted; Apple's log follows" >&2
        [ -n "$ID" ] && xcrun notarytool log "$ID" "${NOTARY_AUTH[@]}" >&2
        exit 1
    fi
}

if [ "$NOTARIZE" = 1 ]; then
    echo "==> Notarizing the app"
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    notarize "$OUT/notarize.zip"
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
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | sed 's/^/    /'
    spctl -a -vv "$APP" 2>&1 | sed 's/^/    /'
fi

if [ "$APPCAST" = 1 ]; then
    SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts" -path '*Sparkle/bin' -type d | head -1)"
    echo "==> Generating the appcast"
    # The private half of GoldenIce's update key is in the keychain under this account name.
    # Only the DMG is listed; generate_appcast keeps earlier versions already in appcast.xml.
    APPCAST_DIR="$OUT/appcast"
    mkdir -p "$APPCAST_DIR"
    cp "$DMG" "$APPCAST_DIR/"
    [ -f "$OUT/appcast.xml" ] && cp "$OUT/appcast.xml" "$APPCAST_DIR/appcast.xml"
    if [ -n "${SPARKLE_KEY_FILE:-}" ]; then
        SPARKLE_KEY=(--ed-key-file "$SPARKLE_KEY_FILE")
    else
        SPARKLE_KEY=(--account "${SPARKLE_ACCOUNT:-goldenice}")
    fi
    "$SPARKLE_BIN/generate_appcast" "${SPARKLE_KEY[@]}" \
        --download-url-prefix "https://github.com/scoopy115/GoldenIce/releases/download/v$VERSION/" \
        -o "$APPCAST_DIR/appcast.xml" "$APPCAST_DIR"
    cp "$APPCAST_DIR/appcast.xml" "$OUT/appcast.xml"
fi

echo
echo "Built GoldenIce $VERSION ($BUILD) in $OUT"
ls -1 "$OUT" | sed 's/^/  /'
