import Foundation
import ImageIO

public struct HistoryItem: Codable, Equatable, Sendable {
    public var id: String
    /// "text" or "image".
    public var type: String
    public var mime: String
    public var sentAt: Int64
    public var receivedAt: Int64
    public var fileName: String
    /// First few hundred characters of a text item, so the menu never reads files.
    public var preview: String?

    public var isImage: Bool { type == "image" }
    public var sentDate: Date { Date(timeIntervalSince1970: Double(sentAt) / 1000) }
}

public enum StoreError: Error, Equatable {
    case invalidID
    case unsupportedType
    case emptyText
    case invalidText
    case textTooLarge
    case invalidImage
    case expired
    case fromFuture

    public var httpStatus: Int {
        switch self {
        case .invalidID: return 400
        case .textTooLarge: return 413
        default: return 422
        }
    }

    public var code: String { String(describing: self) }
}

/// History of received items on disk. Not thread-safe: use from the main thread only.
public final class HistoryStore {
    public static let maxItems = 20
    public static let maxAge: TimeInterval = 10 * 24 * 3600
    public static let maxFutureSkew: TimeInterval = 5 * 60
    public static let maxTextBytes = 1_000_000

    public enum AddResult: Equatable {
        case added
        case duplicate
        /// Valid, but older than the 20 items already kept, so pruned right away.
        case droppedAsOld
    }

    public private(set) var items: [HistoryItem] = []
    /// Item id → sentAt. Kept for as long as the id could still be accepted, so replays are ignored.
    private var seen: [String: Int64] = [:]

    private let itemsDir: URL
    private let indexURL: URL
    private let seenURL: URL
    private let now: () -> Date

    public init(root: URL, now: @escaping () -> Date = Date.init) throws {
        itemsDir = root.appendingPathComponent("items", isDirectory: true)
        indexURL = root.appendingPathComponent("history.json")
        seenURL = root.appendingPathComponent("seen.json")
        self.now = now
        try SecureFile.ensureDirectory(root)
        try SecureFile.ensureDirectory(itemsDir)
        if let data = try? Data(contentsOf: indexURL), let loaded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = loaded
        }
        if let data = try? Data(contentsOf: seenURL), let loaded = try? JSONDecoder().decode([String: Int64].self, from: data) {
            seen = loaded
        }
        prune()
    }

    public func url(for item: HistoryItem) -> URL {
        itemsDir.appendingPathComponent(item.fileName)
    }

    @discardableResult
    public func add(header: ItemHeader, content: Data) throws -> AddResult {
        guard let uuid = UUID(uuidString: header.id) else { throw StoreError.invalidID }
        let id = uuid.uuidString.lowercased()

        let nowMs = Self.millis(now())
        if header.sentAt < nowMs - Int64(Self.maxAge * 1000) { throw StoreError.expired }
        if header.sentAt > nowMs + Int64(Self.maxFutureSkew * 1000) { throw StoreError.fromFuture }
        if seen[id] != nil || items.contains(where: { $0.id == id }) { return .duplicate }

        let ext: String
        var preview: String?
        switch header.type {
        case "text":
            guard header.mime.hasPrefix("text/") else { throw StoreError.unsupportedType }
            guard content.count <= Self.maxTextBytes else { throw StoreError.textTooLarge }
            guard let text = String(data: content, encoding: .utf8) else { throw StoreError.invalidText }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.emptyText }
            preview = String(text.prefix(300))
            ext = "txt"
        case "image":
            guard header.mime.hasPrefix("image/") else { throw StoreError.unsupportedType }
            guard ImageRendering.isDecodable(content) else { throw StoreError.invalidImage }
            ext = Self.fileExtension(forImageMime: header.mime)
        default:
            throw StoreError.unsupportedType
        }

        let item = HistoryItem(id: id, type: header.type, mime: header.mime, sentAt: header.sentAt,
                               receivedAt: nowMs, fileName: "\(id).\(ext)", preview: preview)
        try SecureFile.write(content, to: url(for: item))
        items.append(item)
        seen[id] = header.sentAt
        prune()
        return items.contains(where: { $0.id == id }) ? .added : .droppedAsOld
    }

    /// Applies the age and count limits, removes stray files and persists the result.
    public func prune() {
        let nowMs = Self.millis(now())
        let cutoff = nowMs - Int64(Self.maxAge * 1000)
        items = items.filter { $0.sentAt >= cutoff }.sorted { $0.sentAt > $1.sentAt }
        if items.count > Self.maxItems { items.removeLast(items.count - Self.maxItems) }
        // An id stays useful until its sentAt would be rejected anyway; keep one extra day for clock skew.
        seen = seen.filter { $0.value >= cutoff - 24 * 3600 * 1000 }
        removeStrayFiles()
        save()
    }

    public func clear() {
        items = []
        removeStrayFiles()
        save()
    }

    /// Called after re-pairing: requests sealed with the old key can no longer be opened anyway.
    public func resetSeen() {
        seen = [:]
        save()
    }

    private func removeStrayFiles() {
        let keep = Set(items.map(\.fileName))
        let files = (try? FileManager.default.contentsOfDirectory(atPath: itemsDir.path)) ?? []
        for name in files where !keep.contains(name) {
            try? FileManager.default.removeItem(at: itemsDir.appendingPathComponent(name))
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        try? SecureFile.write(encoder.encode(items), to: indexURL)
        try? SecureFile.write(encoder.encode(seen), to: seenURL)
    }

    static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func fileExtension(forImageMime mime: String) -> String {
        switch mime.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/heic": return "heic"
        case "image/heif": return "heif"
        case "image/webp": return "webp"
        case "image/gif": return "gif"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        default: return "img"
        }
    }
}
