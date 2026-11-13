import Foundation

public enum MenuText {
    public static let textLimit = 50

    /// Collapses all whitespace to single spaces and cuts to `limit` characters with an ellipsis.
    public static func singleLine(_ text: String, limit: Int = textLimit) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit - 1)) + "…"
    }

    public static func imageTitle(sentAt: Date, timeZone: TimeZone = .current) -> String {
        L("Image") + " · " + time(sentAt, timeZone: timeZone)
    }

    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    public static func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("d MMMM yyyy HH:mm")
        return f.string(from: date)
    }
}
