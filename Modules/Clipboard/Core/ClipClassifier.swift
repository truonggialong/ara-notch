import Foundation

/// Decides which kind of clip a piece of pasteboard content is.
public enum ClipClassifier {
    /// - Parameter allowingBareHex: treat six or eight hex digits without `#` as a colour.
    public static func kind(of content: ClipContent, allowingBareHex: Bool = false) -> ClipKind {
        switch content {
        case .image:
            return .image
        case .files:
            return .file
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if isWebURL(trimmed) { return .link }
            if ClipColor.parse(trimmed, allowingBareHex: allowingBareHex) != nil { return .color }
            return .text
        }
    }

    /// True when the whole string is a single http(s) URL with a host.
    private static func isWebURL(_ string: String) -> Bool {
        guard !string.contains(where: \.isWhitespace),
              let components = URLComponents(string: string),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return false }
        return true
    }
}
