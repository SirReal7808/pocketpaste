#!/bin/zsh
# Builds build/MacClip.app (release). Signs with $MACCLIP_SIGN_IDENTITY if set, otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MacClip
swift build -c release --product macclip-send
BIN="$(swift build -c release --show-bin-path)"

APP=build/MacClip.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MacClip" "$APP/Contents/MacOS/MacClip"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp "$BIN/macclip-send" build/macclip-send

IDENTITY="${MACCLIP_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --options runtime --sign - "$APP"
else
    # A secure timestamp is required for notarization.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Built: $PWD/$APP"
echo "Test sender: $PWD/build/macclip-send"
