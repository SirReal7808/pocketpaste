#!/bin/zsh
# Builds a Developer ID signed, notarized MacClip.app and zips it for a GitHub Release.
#
#   scripts/package-release.sh                 # sign, notarize, staple, zip
#   scripts/package-release.sh --skip-notarize # dry run: sign and zip only
#
# Environment:
#   MACCLIP_SIGN_IDENTITY    Developer ID Application identity (default: the first one in the keychain)
#   MACCLIP_NOTARY_PROFILE   notarytool keychain profile (required unless --skip-notarize)
set -euo pipefail
cd "$(dirname "$0")/.."

skip_notarize=false
[[ "${1:-}" == "--skip-notarize" ]] && skip_notarize=true

if [[ -z "${MACCLIP_SIGN_IDENTITY:-}" ]]; then
    MACCLIP_SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
[[ -n "$MACCLIP_SIGN_IDENTITY" ]] || { echo "No Developer ID Application identity found." >&2; exit 1; }
if ! $skip_notarize && [[ -z "${MACCLIP_NOTARY_PROFILE:-}" ]]; then
    echo "Set MACCLIP_NOTARY_PROFILE to a notarytool keychain profile (xcrun notarytool store-credentials)." >&2
    exit 1
fi
export MACCLIP_SIGN_IDENTITY

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP=build/MacClip.app
OUT=build/release
ZIP="$OUT/MacClip-$VERSION-mac.zip"

scripts/build-app.sh
codesign --verify --strict --verbose=2 "$APP"
SIGNATURE="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIGNATURE" == *"(runtime)"* ]] || { echo "Hardened runtime missing." >&2; exit 1; }
[[ "$SIGNATURE" == *$'\nTimestamp='* ]] || { echo "Secure timestamp missing." >&2; exit 1; }

mkdir -p "$OUT"
rm -f "$ZIP"
if ! $skip_notarize; then
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$MACCLIP_NOTARY_PROFILE" --wait
    rm "$OUT/notarize.zip"
    xcrun stapler staple "$APP"
    spctl --assess --type execute --verbose "$APP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "Release zip: $PWD/$ZIP"
$skip_notarize && echo "Not notarized (dry run)."
exit 0
