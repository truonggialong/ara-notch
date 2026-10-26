import Foundation

/// Looks up user-facing strings in the app bundle's `Localizable.strings`.
public enum L10n {
    public static func string(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }
}
