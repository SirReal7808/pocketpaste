# Releasing

How to build the downloads attached to a GitHub Release.

## Version

Bump both apps to the same version:

- Mac: `CFBundleShortVersionString` and `CFBundleVersion` in `mac/Resources/Info.plist`.
- Android: `versionName` and `versionCode` in `android/app/build.gradle.kts`.

## Mac: signed and notarized zip

Needs a **Developer ID Application** certificate in the login keychain and a `notarytool` keychain profile (created once with `xcrun notarytool store-credentials <profile> --apple-id <Apple ID> --team-id <team ID>` and an app-specific password).

```bash
cd mac
MACCLIP_NOTARY_PROFILE=<profile> scripts/package-release.sh
```

The script builds `MacClip.app`, signs it with the first Developer ID identity in the keychain (or `MACCLIP_SIGN_IDENTITY`) with the hardened runtime and a secure timestamp, notarizes and staples it, checks it with `spctl`, and writes `build/release/MacClip-<version>-mac.zip`. `--skip-notarize` is a dry run that only signs and zips.

## Android: signed APK

Needs a release keystore. Keep it and its passwords outside the repo and back them up: an APK signed with another key can't update installed copies.

Create `android/keystore.properties` (ignored by git):

```properties
storeFile=/absolute/path/to/macclip-release.jks
storePassword=…
keyAlias=macclip
keyPassword=…
```

```bash
cd android
./gradlew testDebugUnitTest assembleRelease
cp app/build/outputs/apk/release/app-release.apk ../MacClip-<version>.apk
```

Without `keystore.properties`, `assembleRelease` produces `app-release-unsigned.apk`, which Android won't install.

## Publish

1. Merge to `main` and tag it: `git tag -a v<version> -m "MacClip <version>"` and push the tag.
2. Create the GitHub Release from the tag and attach `MacClip-<version>-mac.zip` and `MacClip-<version>.apk`, with SHA-256 checksums in the notes (`shasum -a 256 <file>`).
