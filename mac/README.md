# PocketPaste · Mac app

Lists the text and images sent from your phone in the menu bar. Click an item to copy it to the clipboard. Protocol and design decisions: [`../SPEC.md`](../SPEC.md).

Requires macOS 13 or later. Building requires Xcode (or the Xcode Command Line Tools).

## Install

Download `PocketPaste-<version>-mac.zip` from [Releases](../../../releases), unzip it and move `PocketPaste.app` to `/Applications`.

The app is not notarized by Apple, so the first time you open it macOS says it can't verify the developer:

1. Open `PocketPaste.app` and close the warning.
2. Go to System Settings › Privacy & Security, scroll down and choose **Open Anyway** next to PocketPaste.
3. Confirm. From then on it opens normally.

If you prefer, build it yourself from source (below).

"Open at Login" only works properly while the app runs from `/Applications`.

## Build

```bash
./scripts/build-app.sh
```

Outputs:
- `build/PocketPaste.app`: the app
- `build/pocketpaste-send`: a sender for testing without a phone

```bash
cp -R build/PocketPaste.app /Applications/ && open /Applications/PocketPaste.app
```

### Signing

The script signs ad hoc by default. macOS may then ask again for the firewall and local network permissions after every rebuild. If you have an Apple developer certificate, use it and the permissions stick:

```bash
security find-identity -p codesigning -v
POCKETPASTE_SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./scripts/build-app.sh
```

Making a release zip: [`../RELEASING.md`](../RELEASING.md).

## First launch and permissions

1. **Pairing window:** on first launch the QR code opens automatically. Scan it from the settings screen of the PocketPaste Android app. You can open it again later with **Pair Again…** in the menu. This creates a new key; the old one stops working.
2. **Incoming connections:** if the macOS firewall is on, it asks whether PocketPaste may accept incoming network connections. Choose **Allow**.
3. **Local network:** allow it if asked. To change it later: System Settings › Privacy & Security › Local Network › PocketPaste.

## Usage

- When something new arrives the icon blinks for 5 seconds, then keeps a dot in its corner. Opening the menu clears the dot.
- The latest 5 items are in the main menu, the next 15 under **Older**. Order and times follow when the item was shared on the phone.
- Click an item to copy it to the clipboard. Images are always copied as PNG. Photos whose long edge is over 4096 pixels are scaled down for the clipboard (a 50 MP photo becomes ~12 MB instead of ~45 MB); the original on disk is unchanged. Hover to see the full date.
- The folder button on the right of an image row shows the file in Finder.
- At most 20 items are kept. Items older than 10 days are deleted.
- The grey line at the bottom of the menu shows the server status and the address it listens on.

The menu is in English, or in Turkish when that is your system language.

Data lives in `~/Library/Application Support/PocketPaste`. The folder is `0700` and the files `0600`, so only your user can read them.

| File | Contents |
|---|---|
| `config.json` | Key and port (default 47812) |
| `history.json` | Item list |
| `items/` | Text and images (images in the format the phone sent) |
| `seen.json` | IDs of items already received (to reject replays) |

## Testing without a phone

`pocketpaste-send` reads the key from the same `config.json` and sends encrypted requests the way the Android app does:

```bash
build/pocketpaste-send ping
```

```bash
build/pocketpaste-send text "Hello Mac"
```

```bash
build/pocketpaste-send image ~/Desktop/screenshot.jpg
```

```bash
build/pocketpaste-send --age 3600 text "as if shared an hour ago"
```

To try things without touching the app's real data, point `POCKETPASTE_HOME` at a separate folder. Give that folder's `config.json` a different port so it doesn't clash with the running app:

```bash
POCKETPASTE_HOME=/tmp/pocketpaste-test build/PocketPaste.app/Contents/MacOS/PocketPaste
```

```bash
POCKETPASTE_HOME=/tmp/pocketpaste-test build/pocketpaste-send text "test"
```

Unit tests:

```bash
swift test
```

## Troubleshooting

**The phone says "Can't reach the Mac"**
1. Look at the grey line at the bottom of the menu. It should read "Listening · 192.168.x.x:47812".
2. Run `build/pocketpaste-send ping` on the Mac. If it returns `200`, the app is fine and the problem is the network.
3. Open `http://<Mac IP>:47812/` in the phone's browser. If you see `{"error":"method"}`, the connection works. If the page doesn't load, check the firewall: System Settings › Network › Firewall › Options › PocketPaste should be "Allow incoming connections".
4. Are the phone and the Mac on the same Wi-Fi? Guest networks usually stop devices from seeing each other.

**Bonjour (mDNS) doesn't work**
Check that the Mac is advertising (quit with Ctrl-C):

```bash
dns-sd -B _pocketpaste._tcp
```

If your Mac's name shows up, the Mac side is fine. Some routers and mesh systems block multicast. The phone then falls back to the IP address from the QR code. With a static IP you don't need anything else. If the IP changed, pair again or enter the address by hand on the phone.

**"Port 47812 is in use by another app"**
Quit the app, change `port` in `config.json`, open the app and pair again.

**`401 unauthorized`**
The phone's key doesn't match the Mac's. Choose **Pair Again…** in the menu and scan the QR code again.

**Resetting everything**
Quit the app, then:

```bash
rm -rf ~/Library/Application\ Support/PocketPaste
```
