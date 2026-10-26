import Foundation

/// How many clips there are of each kind, for the row of kind chips on the clipboard page.
public struct ClipKindTally: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let kind: ClipKind
        public let count: Int
    }

    /// The order the kinds are listed in, whatever the order of the clips.
    public static let order: [ClipKind] = [.text, .link, .image, .color, .file]

    public let total: Int
    /// The kinds that have at least one clip.
    public let kinds: [Entry]

    public init(_ items: [ClipItem]) {
        var counts: [ClipKind: Int] = [:]
        for item in items {
            counts[item.kind, default: 0] += 1
        }
        total = items.count
        kinds = Self.order.compactMap { kind in counts[kind].map { Entry(kind: kind, count: $0) } }
    }

    /// The kind a search is narrowed to by an `@kind` word, if it has one.
    public static func kind(in search: String) -> ClipKind? {
        ClipQuery(search).kind
    }

    /// The search after a kind's chip is clicked: narrowed to that kind, or, when it already
    /// was, no longer narrowed by kind. Everything else typed in the search is kept.
    public static func search(toggling kind: ClipKind, in search: String) -> String {
        let current = Self.kind(in: search)
        var words = search.split(whereSeparator: \.isWhitespace).map(String.init).filter { word in
            guard word.hasPrefix("@") else { return true }
            return ClipQuery.kind(named: String(word.dropFirst())) == nil
        }
        if current != kind {
            words.append("@" + kind.rawValue)
        }
        return words.joined(separator: " ")
    }
}
