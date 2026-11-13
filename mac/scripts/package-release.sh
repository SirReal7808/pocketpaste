#!/bin/zsh
# Builds MacClip.app (ad hoc signed, not notarized) and zips it for a GitHub Release.
# Deliberately not signed with a Developer ID: see RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

unset MACCLIP_SIGN_IDENTITY
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
APP=build/MacClip.app
OUT=build/release
ZIP="$OUT/MacClip-$VERSION-mac.zip"

scripts/build-app.sh
codesign --verify --strict --verbose=2 "$APP"

mkdir -p "$OUT"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP"
echo "Release zip: $PWD/$ZIP"
