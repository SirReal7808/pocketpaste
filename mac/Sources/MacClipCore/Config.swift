import CryptoKit
import Foundation

public enum Paths {
    /// `MACCLIP_HOME` overrides the location, for tests and the CLI.
    public static var root: URL {
        if let custom = ProcessInfo.processInfo.environment["MACCLIP_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacClip", isDirectory: true)
    }
}

/// Files readable only by the current user: directories 0700, files 0600.
public enum SecureFile {
    public static func ensureDirectory(_ url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    /// Writes atomically; the file is created with 0600 so it is never readable by others, even briefly.
    public static func write(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if rename(tmp.path, url.path) != 0 {
            try? FileManager.default.removeItem(at: tmp)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

public enum Base64URL {
    public static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decode(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        s += String(repeating: "=", count: (4 - s.count % 4) % 4)
        return Data(base64Encoded: s)
    }
}

public struct AppConfig: Codable, Equatable {
    public static let defaultPort: UInt16 = 47812

    /// 32 random bytes, base64url.
    public var key: String
    public var port: UInt16

    public init(key: String, port: UInt16 = AppConfig.defaultPort) {
        self.key = key
        self.port = port
    }

    public static func newKey() -> String {
        Base64URL.encode(SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) })
    }

    public var symmetricKey: SymmetricKey? {
        guard let data = Base64URL.decode(key), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    /// Short public fingerprint of the key, advertised over Bonjour so the phone can pick its own Mac.
    public var keyID: String {
        SHA256.hash(data: Data(key.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    public static func load(root: URL) -> AppConfig? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("config.json")) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save(root: URL) throws {
        try SecureFile.ensureDirectory(root)
        try SecureFile.write(JSONEncoder().encode(self), to: root.appendingPathComponent("config.json"))
    }
}

public enum Pairing {
    public static let serviceType = "_macclip._tcp"

    public static func url(host: String, port: UInt16, key: String, name: String) -> String {
        var c = URLComponents()
        c.scheme = "macclip"
        c.host = "pair"
        c.queryItems = [
            URLQueryItem(name: "v", value: "1"),
            URLQueryItem(name: "h", value: host),
            URLQueryItem(name: "p", value: String(port)),
            URLQueryItem(name: "k", value: key),
            URLQueryItem(name: "n", value: name),
        ]
        return c.string ?? ""
    }
}
