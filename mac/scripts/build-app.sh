#!/bin/zsh
# Builds build/PocketPaste.app (release). Signs with $POCKETPASTE_SIGN_IDENTITY if set, otherwise ad hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product PocketPaste
swift build -c release --product pocketpaste-send
BIN="$(swift build -c release --show-bin-path)"

APP=build/PocketPaste.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PocketPaste" "$APP/Contents/MacOS/PocketPaste"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp "$BIN/pocketpaste-send" build/pocketpaste-send

IDENTITY="${POCKETPASTE_SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
    codesign --force --options runtime --sign - "$APP"
else
    # A secure timestamp is required for notarization.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Built: $PWD/$APP"
echo "Test sender: $PWD/build/pocketpaste-send"
