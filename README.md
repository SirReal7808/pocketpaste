# PocketPaste

Share text or an image on your Android phone, click it in your Mac's menu bar, and it is on the Mac's clipboard.

- **Share sheet → menu bar.** Pick "Send to Mac" in Android's share sheet. The item shows up in a menu bar list on the Mac; clicking it copies it. Nothing touches the clipboard until you click.
- **Local and encrypted.** Phone and Mac talk directly over your Wi-Fi. No account, no cloud, no server. Every request is encrypted with AES-256-GCM using a key that only travels inside the pairing QR code.
- **Works when the Mac is away.** If the Mac is asleep or on another network, the phone queues the item and sends it later in the background.

## Download

From [Releases](../../releases):

- `PocketPaste-<version>-mac.zip`: the Mac app (macOS 13+). It is not notarized, so macOS asks you to confirm the first launch ([how](mac/README.md#install)).
- `PocketPaste-<version>.apk`: the Android app (Android 8.0+), installed by hand.

Then open PocketPaste on the Mac, scan the QR code it shows with the Android app, and share something. Details: [Mac app](mac/README.md) · [Android app](android/README.md).

The apps are in English, or in Turkish when that is the system language.

## How it works

1. **Pairing.** The Mac creates a random 256-bit key and shows it, with its IP address and port, as a QR code. The phone scans it. The key never crosses the network.
2. **Sending.** The phone encrypts a small JSON header (ID, type, share time) and the content with AES-256-GCM, binding the request path as associated data, and POSTs it to the Mac over plain HTTP. A wrong key fails authentication and is rejected with `401`.
3. **Finding the Mac.** The phone tries the paired address first, then looks for the Mac with Bonjour (`_pocketpaste._tcp`), matched by a key ID in the TXT record.
4. **Replays and duplicates.** The Mac remembers item IDs for 11 days and rejects anything older than 10 days or more than 5 minutes in the future, so a captured request can't be replayed later and a retried send is never added twice.

The full protocol and design decisions are in [SPEC.md](SPEC.md).

## Repository layout

```
SPEC.md         Protocol (v1) and design decisions
mac/            Swift menu bar app, a test sender (pocketpaste-send) and unit tests
android/        Kotlin share target, encrypted outbox, WorkManager retry, unit tests
RELEASING.md    How to build signed release downloads
```

Built with Swift (AppKit, Network, CryptoKit) and Kotlin (no UI framework, WorkManager, ML Kit code scanner). No third-party dependencies on the Mac.

## Development

```bash
cd mac && swift test && ./scripts/build-app.sh
```

```bash
cd android && ./gradlew testDebugUnitTest assembleDebug
```

## License

[MIT](LICENSE)
