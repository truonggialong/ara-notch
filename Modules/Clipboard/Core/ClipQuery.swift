/// A search typed by the user: free text plus optional `@kind` and `@app` filters.
public struct ClipQuery: Equatable, Sendable {
    public let kind: ClipKind?
    public let app: String?
    public let text: String

    public init(_ raw: String) {
        var kind: ClipKind?
        var app: String?
        var words: [Substring] = []

        for word in raw.split(whereSeparator: \.isWhitespace) {
            guard word.hasPrefix("@") else {
                words.append(word)
                continue
            }
            let name = String(word.dropFirst())
            guard !name.isEmpty else { continue }
            if let match = Self.kind(named: name) {
                kind = match
            } else {
                app = name
            }
        }

        self.kind = kind
        self.app = app
        text = words.joined(separator: " ")
    }

    /// The kind a filter word names: its English name, or the Vietnamese one, with or without
    /// accents (`@ảnh`, `@anh`).
    static func kind(named name: String) -> ClipKind? {
        if let kind = ClipKind(rawValue: name.lowercased()) { return kind }
        return vietnameseKinds[SearchFolding.fold(name)]
    }

    private static let vietnameseKinds: [String: ClipKind] = [
        "anh": .image, "mau": .color, "tep": .file, "chu": .text, "lienket": .link,
    ]

    public var isEmpty: Bool {
        kind == nil && app == nil && text.isEmpty
    }

    public func matches(_ item: ClipItem) -> Bool {
        if let kind, item.kind != kind { return false }
        if let app {
            let needle = SearchFolding.fold(app)
            let candidates = [item.source.appName, item.source.bundleID].compactMap { $0 }
            guard candidates.contains(where: { SearchFolding.fold($0).contains(needle) }) else { return false }
        }
        if !text.isEmpty {
            // The clip's own text, the name the user gave it, and text read from an image.
            let needle = SearchFolding.fold(text)
            let haystacks = [item.text, item.title, item.recognizedText].compactMap { $0 }
            guard haystacks.contains(where: { SearchFolding.fold($0).contains(needle) }) else { return false }
        }
        return true
    }
}
