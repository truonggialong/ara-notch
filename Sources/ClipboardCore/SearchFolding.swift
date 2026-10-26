import Foundation

/// Normalises text so that search ignores case and diacritics.
public enum SearchFolding {
    private static let locale = Locale(identifier: "en_US_POSIX")

    public static func fold(_ string: String) -> String {
        string
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            // "đ" is a letter of its own, not "d" plus a mark, so folding leaves it alone.
            .replacingOccurrences(of: "đ", with: "d")
    }
}
