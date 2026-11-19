# Releasing

How to build the downloads attached to a GitHub Release.

## Version

Bump both apps to the same version:

- Mac: `CFBundleShortVersionString` and `CFBundleVersion` in `mac/Resources/Info.plist`.
- Android: `versionName` and `versionCode` in `android/app/build.gradle.kts`.

## Mac: unsigned zip

```bash
cd mac
scripts/package-release.sh
```

The script builds `PocketPaste.app` with an ad hoc signature and writes `build/release/PocketPaste-<version>-mac.zip`.

The release is deliberately **not** signed with a Developer ID or notarized, so it stays independent of any Apple developer account. Users confirm the first launch once in System Settings (see the Mac README).

## Android: signed APK

Needs a release keystore. Keep it and its passwords outside the repo and back them up: an APK signed with another key can't update installed copies.

Create `android/keystore.properties` (ignored by git):

```properties
storeFile=/absolute/path/to/pocketpaste-release.jks
storePassword=…
keyAlias=pocketpaste
keyPassword=…
```

```bash
cd android
./gradlew testDebugUnitTest assembleRelease
cp app/build/outputs/apk/release/app-release.apk ../PocketPaste-<version>.apk
```

Without `keystore.properties`, `assembleRelease` produces `app-release-unsigned.apk`, which Android won't install.

## Publish

1. Merge to `main` and tag it: `git tag -a v<version> -m "PocketPaste <version>"` and push the tag.
2. Create the GitHub Release from the tag and attach `PocketPaste-<version>-mac.zip` and `PocketPaste-<version>.apk`, with SHA-256 checksums in the notes (`shasum -a 256 <file>`).
