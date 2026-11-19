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

The release keystore (`pocketpaste-release.jks`, alias `pocketpaste`) is **not kept on the development machine**. The only copy is in the maintainer's private cloud storage, and its password is in the maintainer's password manager. Never commit it or leave a copy behind: an APK signed with another key can't update installed copies, so the key must never change or get lost.

1. Download the keystore to a temporary location.
2. Build, entering the password when asked (it is read from the terminal and never written to disk):

   ```bash
   cd android
   scripts/build-release.sh /tmp/path/pocketpaste-release.jks
   ```

   The script runs the unit tests, builds, verifies the signature and writes `build/release/PocketPaste-<version>.apk` with its SHA-256.
3. Delete the temporary keystore copy.

Without the keystore, `./gradlew assembleRelease` produces `app-release-unsigned.apk`, which Android won't install.

## Publish

1. Merge to `main` and tag it: `git tag -a v<version> -m "PocketPaste <version>"` and push the tag.
2. Create the GitHub Release from the tag and attach `mac/build/release/PocketPaste-<version>-mac.zip` and `android/build/release/PocketPaste-<version>.apk`, with SHA-256 checksums in the notes (`shasum -a 256 <file>`).
