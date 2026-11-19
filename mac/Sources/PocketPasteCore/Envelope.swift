import CryptoKit
import Foundation

/// Metadata sent with every request, inside the encrypted envelope.
public struct ItemHeader: Codable, Equatable, Sendable {
    public var id: String
    /// "text", "image" or "ping".
    public var type: String
    public var mime: String
    /// Milliseconds since 1970, set on the phone when the user shared the item.
    public var sentAt: Int64

    public init(id: String, type: String, mime: String, sentAt: Int64) {
        self.id = id
        self.type = type
        self.mime = mime
        self.sentAt = sentAt
    }
}

public enum EnvelopeError: Error, Equatable {
    case tooShort
    case decryptFailed
    case malformedHeader
}

/// Wire format (see SPEC.md):
///   body      = nonce(12) || ciphertext || tag(16)        AES-256-GCM, AAD = request path
///   plaintext = headerLength(4, big-endian) || header JSON || content
public enum Envelope {
    static let nonceSize = 12
    static let tagSize = 16

    public static func seal(header: ItemHeader, content: Data, key: SymmetricKey, path: String) throws -> Data {
        let headerData = try JSONEncoder().encode(header)
        var plain = Data(capacity: 4 + headerData.count + content.count)
        let length = UInt32(headerData.count)
        plain.append(contentsOf: [UInt8(length >> 24 & 0xff), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
        plain.append(headerData)
        plain.append(content)
        let box = try AES.GCM.seal(plain, using: key, authenticating: Data(path.utf8))
        guard let combined = box.combined else { throw EnvelopeError.malformedHeader }
        return combined
    }

    public static func open(_ body: Data, key: SymmetricKey, path: String) throws -> (ItemHeader, Data) {
        guard body.count >= nonceSize + tagSize + 4 else { throw EnvelopeError.tooShort }
        let plain: Data
        do {
            let box = try AES.GCM.SealedBox(combined: body)
            plain = try AES.GCM.open(box, using: key, authenticating: Data(path.utf8))
        } catch {
            throw EnvelopeError.decryptFailed
        }

        let bytes = [UInt8](plain)
        let length = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        guard bytes.count >= 4 + length else { throw EnvelopeError.malformedHeader }
        let headerData = Data(bytes[4..<(4 + length)])
        guard let header = try? JSONDecoder().decode(ItemHeader.self, from: headerData) else {
            throw EnvelopeError.malformedHeader
        }
        return (header, Data(bytes[(4 + length)...]))
    }
}
