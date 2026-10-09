#!/bin/bash
#
# Builds a GoldenIce release: a Developer ID signed, notarized Ice.app in a zip, plus a
# Sparkle appcast entry signed with GoldenIce's own update key. Nothing is uploaded; the
# printed steps say what to publish where. See docs/RELEASING.md.
#
# Usage: Scripts/release.sh [--skip-notarize]
#
# Needs once:
#   - A Developer ID Application certificate in the keychain.
#   - A notarytool keychain profile named "GoldenIce" (xcrun notarytool store-credentials).
#   - GoldenIce's Sparkle key in the keychain (Sparkle's generate_keys, see docs/RELEASING.md),
#     with its public half in Ice/Resources/Info.plist as SUPublicEDKey.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${DERIVED:-/tmp/goldenice-release}"
OUT="${OUT:-$ROOT/build/releases}"
NOTARIZE=1
[ "${1:-}" = "--skip-notarize" ] && NOTARIZE=0

TEAM="$(security find-certificate -c "Developer ID Application" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p' | head -1)"
[ -n "$TEAM" ] || { echo "error: no Developer ID Application certificate" >&2; exit 1; }

echo "==> Building Release, signed with Developer ID ($TEAM)"
xcodebuild -project "$ROOT/Ice.xcodeproj" -scheme Ice -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" \
    PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES \
    | tail -1

APP="$DERIVED/Build/Products/Release/Ice.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Contents/Info.plist")"
mkdir -p "$OUT"
ZIP="$OUT/GoldenIce-$VERSION.zip"

codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$NOTARIZE" = 1 ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$ZIP" --keychain-profile GoldenIce --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
fi

SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts" -path '*Sparkle/bin' -type d | head -1)"
echo "==> Generating the appcast"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/scoopy115/GoldenIce/releases/download/v$VERSION/" \
    -o "$OUT/appcast.xml" "$OUT"

cat <<NEXT

Built GoldenIce $VERSION ($BUILD):
  $ZIP
  $OUT/appcast.xml

To publish (by hand, when you decide to):
  1. Create a GitHub release tagged v$VERSION and attach the zip.
  2. Attach appcast.xml to the same release, so the feed URL
     https://github.com/scoopy115/GoldenIce/releases/latest/download/appcast.xml serves it.
NEXT
