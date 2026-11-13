import Foundation

/// Looks up a user-facing string in the app bundle's Localizable.strings. The key is the English text,
/// so builds without the .lproj folders (unit tests, `swift run`) show English.
public func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// `L(key)` used as a format string, e.g. `L("Port %@ is in use by another app", port)`.
public func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
