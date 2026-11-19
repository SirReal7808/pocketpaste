# PocketPaste · Android app

Adds "Send to Mac" to the share sheet. Sends the chosen text or images, encrypted, to the Mac on the same Wi-Fi. If the Mac can't be reached, it queues them and tries again later on its own. Protocol and design decisions: [`../SPEC.md`](../SPEC.md).

Requires Android 8.0 (API 26) or later. Scanning the QR code needs Google Play services; without them, use manual entry.

The app is in English, or in Turkish when that is the phone's language.

## Install

Download `PocketPaste-<version>.apk` from [Releases](../../../releases) and open it on the phone. Android asks for permission to install from unknown sources; give it only to the app you opened the file with.

An app built on your own machine is signed with a different key than the release APK. Android won't update one with the other: uninstall first (the pairing and any queued items are deleted), then install and pair again.

## Build

Open the `android` folder in Android Studio and choose **Build › Build APK(s)**, or build from the command line (needs JDK 17 and the Android SDK):

```bash
./gradlew assembleDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`

- **Over USB:** with Developer options › USB debugging on:
  ```bash
  adb install -r app/build/outputs/apk/debug/app-debug.apk
  ```
- **By hand:** copy the APK to the phone and open it in a file manager.

To update, install an APK built on the same machine; a different debug key makes Android refuse the update.

Making a signed release APK: [`../RELEASING.md`](../RELEASING.md).

## Pairing

1. On the Mac, PocketPaste shows the QR code on first launch. Later you can open it with **Pair Again…** in the menu.
2. On the phone, open PocketPaste and tap **Scan QR code**.
3. The app runs a connection test automatically and should show "Connected ✓".

If the QR code won't scan, type the address, port and key shown in the Mac's window under **Manual entry** and tap **Save**.

## Usage

In any app, select text or open an image or screenshot and choose **Share › Send to Mac**.
- Nothing opens on screen. Within a few seconds a short message appears: "Sent" or "Can't reach the Mac, queued". The app doesn't stay in Recents and shows no notification.
- If you pick several images, each becomes its own item on the Mac.
- Limits: 25 MB per image, 1 MB of text.

### Queue

What you share while the Mac is off or on another network waits on the phone:
- While the phone is on Wi-Fi it is retried in the background about every 15 minutes. Android's battery saving can make the delay a little longer.
- To send right away, open PocketPaste and tap **Send now**.
- At most 20 items wait. Items older than 10 days are deleted. On the Mac, items are ordered by when you shared them.

## Permissions

No runtime permission is asked. The manifest only has `INTERNET` and `ACCESS_NETWORK_STATE`.
- **Plain HTTP:** since Android 9 plain HTTP is off by default; `res/xml/network_security_config.xml` turns it on. The content itself is encrypted with AES-256-GCM and the key never travels over the network.
- **Backup:** off (`allowBackup="false"`), so the pairing key doesn't go to Google backup.
- **Local network permission:** newer Android versions may add a separate permission for local network access. The app targets `targetSdk 36`. If a "nearby devices / local network" permission is ever asked, allow it.

## Troubleshooting

**"Can't reach the Mac"**
1. Is PocketPaste running on the Mac? The grey line at the bottom of its menu should read "Listening · IP:port".
2. Are the phone and the Mac on the same Wi-Fi? A guest network or "AP isolation" stops devices from seeing each other.
3. Open `http://<Mac IP>:47812/` in the phone's browser. If you see `{"error":"method"}`, the network is fine and the problem is the key: pair again.
4. If the page doesn't load, the Mac's firewall may not allow incoming connections to PocketPaste (see the Mac README).

**Bonjour (mDNS) doesn't work**
The app first tries the IP from pairing and only then searches with Bonjour. With a static IP you never need Bonjour. Some routers and mesh systems block multicast; if the Mac's IP then changes, update the address in the app or pair again.

**"The key doesn't match"**
The Mac was paired again. Scan the QR code again. Queued items are kept.

**Queued items never go out**
Some manufacturers (Xiaomi, Huawei, some Samsung settings) stop background work. Remove the restriction under Settings › Apps › PocketPaste › Battery, or use **Send now**.

## Tests

```bash
./gradlew testDebugUnitTest
```

End-to-end test against a running Mac app (ping, text, image, wrong key). The key comes from `config.json` on the Mac:

```bash
./gradlew testDebugUnitTest -PpocketpasteTestKey=<key> -PpocketpasteTestPort=47812 -PpocketpasteTestHost=<Mac IP>
```
