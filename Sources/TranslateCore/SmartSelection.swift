import CoreGraphics
import Foundation

/// Tells a press and release that may have selected text from a plain click.
public enum SelectionGesture {
    /// A pointer that moved less than this between press and release did not drag.
    public static let minimumDrag: CGFloat = 4

    /// A drag, or a double or triple click, may have selected text; a plain click has not.
    public static func maySelect(down: CGPoint, up: CGPoint, clickCount: Int) -> Bool {
        if clickCount >= 2 { return true }
        return hypot(up.x - down.x, up.y - down.y) >= minimumDrag
    }
}

/// What the bar beside a fresh selection can do with it.
public enum SelectionAction: String, CaseIterable, Sendable {
    case copy
    case translate
    case search
    case openLink
}

/// A piece of text the user just selected, and what can be done with it.
public struct SmartSelection: Equatable, Sendable {
    /// Longer selections get no bar: whole documents are not what the bar is for.
    public static let maxLength = 5000
    /// Longer text is not a search query.
    static let maxSearchLength = 200

    /// The selected text without the space around it.
    public let text: String

    /// Nil when nothing but space is selected, or too much.
    public init?(_ raw: String?) {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty, trimmed.count <= Self.maxLength
        else { return nil }
        text = trimmed
    }

    /// The selection as a web link, when it is one and nothing else.
    public var link: URL? {
        guard !text.contains(where: \.isWhitespace), let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }

    public var actions: [SelectionAction] {
        if link != nil { return [.copy, .openLink] }
        return text.count <= Self.maxSearchLength ? [.copy, .translate, .search] : [.copy, .translate]
    }

    /// A web search for the text. The text travels in the address, as with any search.
    public var searchURL: URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let query = text.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://www.google.com/search?q=\(query)")
    }
}

/// Keeps the bar from coming back for a selection it was already shown for: a later drag, of
/// a window for instance, finds the same text still selected.
public struct SelectionTracker: Sendable {
    private var last: (pid: Int32, text: String)?

    public init() {}

    /// Whether to show the bar for what is selected now in the app with this process id.
    public mutating func shouldShow(_ selection: SmartSelection?, pid: Int32) -> Bool {
        guard let selection else {
            last = nil
            return false
        }
        if let last, last.pid == pid, last.text == selection.text { return false }
        last = (pid, selection.text)
        return true
    }

    /// A plain click ends the selection; the same text selected again is a new selection.
    public mutating func reset() {
        last = nil
    }
}
