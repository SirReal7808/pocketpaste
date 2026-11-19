import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PocketPasteCore

final class EnvelopeTests: XCTestCase {
    let key = SymmetricKey(size: .bits256)
    let header = ItemHeader(id: UUID().uuidString, type: "text", mime: "text/plain", sentAt: 1_700_000_000_000)

    func testRoundTrip() throws {
        let body = try Envelope.seal(header: header, content: Data("merhaba".utf8), key: key, path: "/v1/items")
        let (h, content) = try Envelope.open(body, key: key, path: "/v1/items")
        XCTAssertEqual(h, header)
        XCTAssertEqual(String(data: content, encoding: .utf8), "merhaba")
    }

    func testWrongKeyFails() throws {
        let body = try Envelope.seal(header: header, content: Data("x".utf8), key: key, path: "/v1/items")
        XCTAssertThrowsError(try Envelope.open(body, key: SymmetricKey(size: .bits256), path: "/v1/items")) {
            XCTAssertEqual($0 as? EnvelopeError, .decryptFailed)
        }
    }

    func testPathIsAuthenticated() throws {
        let body = try Envelope.seal(header: header, content: Data("x".utf8), key: key, path: "/v1/ping")
        XCTAssertThrowsError(try Envelope.open(body, key: key, path: "/v1/items"))
    }

    func testTamperingFails() throws {
        var body = try Envelope.seal(header: header, content: Data("x".utf8), key: key, path: "/v1/items")
        body[20] ^= 1
        XCTAssertThrowsError(try Envelope.open(body, key: key, path: "/v1/items"))
    }

    func testTooShort() {
        XCTAssertThrowsError(try Envelope.open(Data([1, 2, 3]), key: key, path: "/v1/items")) {
            XCTAssertEqual($0 as? EnvelopeError, .tooShort)
        }
    }

    /// Fixed vector shared with the Android tests: both sides must produce and accept the same bytes.
    func testKnownVector() throws {
        let key = SymmetricKey(data: Data(0..<32))
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 7, count: 12))
        let headerJSON = Data(#"{"id":"00000000-0000-0000-0000-000000000001","mime":"text/plain","sentAt":1,"type":"text"}"#.utf8)
        var plain = Data([0, 0, 0, UInt8(headerJSON.count)])
        plain.append(headerJSON)
        plain.append(Data("hi".utf8))
        let box = try AES.GCM.seal(plain, using: key, nonce: nonce, authenticating: Data("/v1/items".utf8))
        let (h, content) = try Envelope.open(box.combined!, key: key, path: "/v1/items")
        XCTAssertEqual(h.id, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(content, Data("hi".utf8))
        print("KNOWN_VECTOR_HEX", box.combined!.map { String(format: "%02x", $0) }.joined())
    }
}

final class ConfigTests: XCTestCase {
    func testKeyRoundTrip() {
        let config = AppConfig(key: AppConfig.newKey())
        XCTAssertEqual(config.key.count, 43)
        XCTAssertNotNil(config.symmetricKey)
        XCTAssertEqual(config.keyID.count, 8)
    }

    func testPairingURL() {
        let url = Pairing.url(host: "192.168.1.10", port: 47812, key: "abc-_", name: "Mert’in MacBook'u")
        let c = URLComponents(string: url)!
        XCTAssertEqual(c.scheme, "pocketpaste")
        XCTAssertEqual(c.host, "pair")
        XCTAssertEqual(c.queryItems?.first { $0.name == "n" }?.value, "Mert’in MacBook'u")
        XCTAssertEqual(c.queryItems?.first { $0.name == "k" }?.value, "abc-_")
    }

    func testFilePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try AppConfig(key: AppConfig.newKey()).save(root: root)
        let dirPerms = try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions] as? Int
        let filePerms = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("config.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(dirPerms, 0o700)
        XCTAssertEqual(filePerms, 0o600)
    }
}

final class HistoryStoreTests: XCTestCase {
    var root: URL!
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    func makeStore() throws -> HistoryStore {
        try HistoryStore(root: root, now: { [unowned self] in self.now })
    }

    func header(_ type: String = "text", mime: String = "text/plain", ageSeconds: Double = 0, id: String = UUID().uuidString) -> ItemHeader {
        ItemHeader(id: id, type: type, mime: mime, sentAt: Int64((now.timeIntervalSince1970 - ageSeconds) * 1000))
    }

    func testAddTextAndPersist() throws {
        let store = try makeStore()
        XCTAssertEqual(try store.add(header: header(), content: Data("merhaba dünya".utf8)), .added)
        let reloaded = try makeStore()
        XCTAssertEqual(reloaded.items.count, 1)
        XCTAssertEqual(reloaded.items[0].preview, "merhaba dünya")
        let perms = try FileManager.default.attributesOfItem(atPath: reloaded.url(for: reloaded.items[0]).path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testDuplicateIgnoredEvenAfterClear() throws {
        let store = try makeStore()
        let h = header()
        XCTAssertEqual(try store.add(header: h, content: Data("a".utf8)), .added)
        XCTAssertEqual(try store.add(header: h, content: Data("a".utf8)), .duplicate)
        store.clear()
        XCTAssertEqual(try store.add(header: h, content: Data("a".utf8)), .duplicate)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testOrderedBySentAtNewestFirst() throws {
        let store = try makeStore()
        try store.add(header: header(ageSeconds: 60), content: Data("older".utf8))
        try store.add(header: header(ageSeconds: 3600), content: Data("oldest, arrived last".utf8))
        try store.add(header: header(ageSeconds: 0), content: Data("newest".utf8))
        XCTAssertEqual(store.items.map(\.preview), ["newest", "older", "oldest, arrived last"])
    }

    func testCountLimit() throws {
        let store = try makeStore()
        for i in 0..<25 {
            try store.add(header: header(ageSeconds: Double(100 - i)), content: Data("item \(i)".utf8))
        }
        XCTAssertEqual(store.items.count, 20)
        XCTAssertEqual(store.items.first?.preview, "item 24")
        XCTAssertEqual(store.items.last?.preview, "item 5")
        let files = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("items").path)
        XCTAssertEqual(files.count, 20)
        XCTAssertEqual(try store.add(header: header(ageSeconds: 1000), content: Data("too old to fit".utf8)), .droppedAsOld)
    }

    func testAgeLimitAndPrune() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.add(header: header(ageSeconds: 11 * 86400), content: Data("x".utf8))) {
            XCTAssertEqual($0 as? StoreError, .expired)
        }
        XCTAssertThrowsError(try store.add(header: header(ageSeconds: -600), content: Data("x".utf8))) {
            XCTAssertEqual($0 as? StoreError, .fromFuture)
        }
        try store.add(header: header(ageSeconds: 9 * 86400), content: Data("x".utf8))
        now += 2 * 86400
        store.prune()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testValidation() throws {
        let store = try makeStore()
        XCTAssertThrowsError(try store.add(header: header(id: "../../etc/passwd"), content: Data("x".utf8))) {
            XCTAssertEqual($0 as? StoreError, .invalidID)
        }
        XCTAssertThrowsError(try store.add(header: header(), content: Data("  \n".utf8))) {
            XCTAssertEqual($0 as? StoreError, .emptyText)
        }
        XCTAssertThrowsError(try store.add(header: header("file", mime: "application/pdf"), content: Data("x".utf8))) {
            XCTAssertEqual($0 as? StoreError, .unsupportedType)
        }
        XCTAssertThrowsError(try store.add(header: header("image", mime: "image/png"), content: Data("not an image".utf8))) {
            XCTAssertEqual($0 as? StoreError, .invalidImage)
        }
    }

    func testImageStoredAsSentAndCopiedAsPNG() throws {
        let store = try makeStore()
        let jpeg = try Self.makeImage(type: .jpeg, width: 40, height: 20)
        XCTAssertEqual(try store.add(header: header("image", mime: "image/jpeg"), content: jpeg), .added)
        let item = store.items[0]
        XCTAssertTrue(item.fileName.hasSuffix(".jpg"))
        XCTAssertEqual(try Data(contentsOf: store.url(for: item)), jpeg)
        let png = try XCTUnwrap(ImageRendering.pngData(contentsOf: store.url(for: item)))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let thumb = try XCTUnwrap(ImageRendering.orientedImage(at: store.url(for: item), maxPixelSize: 10))
        XCTAssertEqual(thumb.width, 10)
    }

    func testLargeImagesAreScaledDownForPasteboardOnly() throws {
        let store = try makeStore()
        try store.add(header: header("image", mime: "image/png"), content: try Self.makeImage(type: .png, width: 5000, height: 100))
        try store.add(header: header("image", mime: "image/png", ageSeconds: 1), content: try Self.makeImage(type: .png, width: 1200, height: 2600))
        func pngSize(_ item: HistoryItem) throws -> (Int, Int) {
            let png = try XCTUnwrap(ImageRendering.pngData(contentsOf: store.url(for: item)))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
            let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            return (props[kCGImagePropertyPixelWidth] as! Int, props[kCGImagePropertyPixelHeight] as! Int)
        }
        let (bigW, bigH) = try pngSize(store.items[0])
        XCTAssertEqual(bigW, 4096)
        XCTAssertEqual(bigH, 82, accuracy: 1)
        let (smallW, smallH) = try pngSize(store.items[1])
        XCTAssertEqual(smallW, 1200)
        XCTAssertEqual(smallH, 2600)
        // The original on disk is untouched.
        let original = try XCTUnwrap(CGImageSourceCreateWithURL(store.url(for: store.items[0]) as CFURL, nil))
        let originalProps = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(original, 0, nil) as? [CFString: Any])
        XCTAssertEqual(originalProps[kCGImagePropertyPixelWidth] as? Int, 5000)
    }

    static func makeImage(type: UTType, width: Int, height: Int) throws -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }
}

final class MenuTextTests: XCTestCase {
    func testSingleLine() {
        XCTAssertEqual(MenuText.singleLine("  a\n\n b\tc  "), "a b c")
        let long = String(repeating: "x", count: 80)
        let cut = MenuText.singleLine(long)
        XCTAssertEqual(cut.count, 50)
        XCTAssertTrue(cut.hasSuffix("…"))
    }

    func testImageTitle() {
        let date = Date(timeIntervalSince1970: 7 * 3600 + 48 * 60)
        XCTAssertEqual(MenuText.imageTitle(sentAt: date, timeZone: TimeZone(identifier: "UTC")!), "Image · 07:48")
    }
}
