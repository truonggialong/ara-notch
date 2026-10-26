import Foundation

/// The look of the app's windows.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system, dark, light
}

/// Finding a setting by typing part of its name.
public enum SettingsSearch {
    /// One section of the Settings window and the names of what is in it.
    public struct Section: Equatable, Sendable {
        public let id: String
        public let title: String
        public var phrases: [String]

        public init(id: String, title: String, phrases: [String]) {
            self.id = id
            self.title = title
            self.phrases = phrases
        }
    }

    /// The sections that match, in their order. A section found by what is in it carries the
    /// matching names, so the list can say why it is there; one found by its own name, or kept
    /// because nothing was typed, carries none.
    public static func results(for query: String, in sections: [Section]) -> [Section] {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return sections.map { Section(id: $0.id, title: $0.title, phrases: []) } }
        return sections.compactMap { section in
            if fold(section.title).contains(needle) {
                return Section(id: section.id, title: section.title, phrases: [])
            }
            let matches = section.phrases.filter { fold($0).contains(needle) }
            return matches.isEmpty ? nil : Section(id: section.id, title: section.title, phrases: matches)
        }
    }

    /// Lower case, without accents; đ counts as d.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
    }
}
