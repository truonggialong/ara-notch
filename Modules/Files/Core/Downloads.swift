import Foundation

/// The downloads under way into the Downloads folder, as the closed notch shows them: one ring
/// for all of them together, and how many there are.
public struct DownloadTally: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var name: String
        /// 0…1; nil while the size is not known yet.
        public var fraction: Double?

        public init(name: String, fraction: Double?) {
            self.name = name
            self.fraction = fraction
        }
    }

    public var items: [String: Item] = [:]

    public init() {}

    public var isEmpty: Bool { items.isEmpty }

    /// All downloads together, each counting the same; one of unknown size counts as not begun.
    public var fraction: Double {
        guard !items.isEmpty else { return 0 }
        return items.values.map { min(max($0.fraction ?? 0, 0), 1) }.reduce(0, +) / Double(items.count)
    }

    /// "64%" for one download, "3 · 41%" for several.
    public var label: String {
        let percent = "\(Int((fraction * 100).rounded(.down)))%"
        return items.count > 1 ? "\(items.count) · \(percent)" : percent
    }
}
