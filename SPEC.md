# PocketPaste: a local clipboard bridge from phone to Mac

Sends text or an image chosen in Android's share sheet to a Mac on the same Wi-Fi. On the Mac, clicking an item in the menu bar list copies it to the clipboard.

## Decisions

### General
- Local network only, phone → Mac only, text and images only.
- Transport is plain HTTP. Content is encrypted with AES-256-GCM using a 256-bit key shared at pairing. The key never travels over the network.
- One phone is paired. Pairing again creates a new key and the old one stops working.
- Pairing uses a QR code shown on the Mac.
- Discovery: first the IP and port from pairing (fastest with a static IP); if unreachable, Bonjour (`_pocketpaste._tcp`, the TXT record `kid` picks the right Mac).
- User-facing text is English, with a Turkish translation used when the system language is Turkish.

### Mac app
- Swift, menu bar only (no Dock icon).
- List: the first 5 items in the main menu, the next 15 under "Older". Text and images share one list.
- Order and the time shown: when the item was **shared** on the phone (not when it arrived).
- Text: collapsed to one line, cut at 50 characters.
- Image: a small preview and "Image · HH:MM".
- Clicking copies to the clipboard. Images always go to the clipboard as **PNG**; if the long edge is over 4096 pixels, the clipboard copy is scaled down to that size (the original on disk is unchanged). Incoming content is never written to the clipboard on its own.
- Stored on disk (`~/Library/Application Support/PocketPaste`, folder 0700, files 0600). Images are stored in the format the phone sent.
- At most 20 items; items older than 10 days are deleted automatically.
- When a new item arrives the icon blinks for 5 seconds, then keeps a dot. Opening the menu clears the dot. No macOS notifications.
- Menu: Clear History, Pair Again, Open at Login, Quit.

### Android app
- Kotlin, APK installed by hand (no Play Store).
- "Send to Mac" in the share sheet. When several images are shared, each becomes its own item.
- Sharing opens an invisible screen: the content is written to a queue in the app's private storage, sending is tried right away for about 3 seconds, a short Toast is shown ("Sent" or "Can't reach the Mac, queued") and the screen closes. It does not stay in Recents, shows no notification and runs no foreground service.
- Items not sent are retried in the background by WorkManager while on Wi-Fi (a delay of a few minutes up to ~15 minutes is possible).
- Queue on the phone: at most 20 items; items older than 10 days are deleted.
- Settings screen: QR scan, manual entry, connection test, number of waiting items and "Send now".

## Protocol (v1)

### Pairing QR content
```
pocketpaste://pair?v=1&h=<ipv4>&p=<port>&k=<base64url key, 32 bytes>&n=<Mac name>
```

### Requests
One kind of endpoint, binary body:

- `POST /v1/items`: sends an item.
- `POST /v1/ping`: connection and key test.

Body: `nonce (12 bytes) || AES-256-GCM ciphertext || tag (16 bytes)`. AAD: the request path (`/v1/items` or `/v1/ping`).

Decrypted content:
```
header length (4 bytes, big-endian) || header JSON (UTF-8) || raw content bytes
```
Header JSON:
```json
{"id": "<UUID>", "type": "text" | "image" | "ping", "mime": "text/plain" | "image/png" | ..., "sentAt": <epoch ms>}
```

### Responses
- `200` accepted (also `200` if the same `id` arrived before; it is not added again).
- `400` malformed request, `401` decryption failed (wrong key), `404` unknown path, `413` too large, `422` unsupported type or expired (`sentAt` older than 10 days or more than 5 minutes in the future).

### Limits
- Body at most 30 MB, text at most 1 MB.
- The Mac keeps the `id`s it has seen for 11 days. Replay protection relies on these IDs.
