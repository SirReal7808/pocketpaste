#!/bin/zsh
# Builds the signed release APK. The keystore lives off this machine (see RELEASING.md):
# pass a temporary copy of it; the password is asked for and never written to disk.
#   scripts/build-release.sh /path/to/pocketpaste-release.jks
set -euo pipefail
cd "$(dirname "$0")/.."

KEYSTORE="${1:?usage: scripts/build-release.sh /path/to/pocketpaste-release.jks}"
[[ -f "$KEYSTORE" ]] || { echo "Keystore not found: $KEYSTORE" >&2; exit 1; }

if [[ -z "${POCKETPASTE_KEYSTORE_PASSWORD:-}" ]]; then
  read -rs "POCKETPASTE_KEYSTORE_PASSWORD?Keystore password: "
  echo
fi
export POCKETPASTE_KEYSTORE="${KEYSTORE:A}" POCKETPASTE_KEYSTORE_PASSWORD

VERSION="$(sed -n 's/.*versionName = "\(.*\)".*/\1/p' app/build.gradle.kts)"
OUT="build/release/PocketPaste-$VERSION.apk"

./gradlew --no-daemon testDebugUnitTest assembleRelease
mkdir -p build/release
cp app/build/outputs/apk/release/app-release.apk "$OUT"

SDK="$(sed -n 's/^sdk.dir=//p' local.properties)"
APKSIGNER="$(ls -d "$SDK"/build-tools/*/apksigner | tail -1)"
"$APKSIGNER" verify --print-certs "$OUT" | grep -E 'DN|SHA-256'
shasum -a 256 "$OUT"
echo "Release APK: $PWD/$OUT"
