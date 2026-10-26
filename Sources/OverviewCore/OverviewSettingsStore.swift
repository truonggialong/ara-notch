import Foundation

/// Reads and writes the overview's arrangement. The keys keep the `shell.` names they had when
/// the shell kept the arrangement, so a page arranged before stays as it was.
public struct OverviewSettingsStore {
    public enum Key {
        public static let arrangement = "shell.overviewArrangement"
        public static let hiddenWidgets = "shell.hiddenOverviewWidgets"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The tiles of the overview page turned off before its tiles could be arranged; read
    /// once, to start the arrangement from.
    private var hiddenWidgets: [String] {
        defaults.object(forKey: Key.hiddenWidgets) as? [String] ?? []
    }

    /// The overview's tiles in their order, each with its size, as `"<widget>:<size>"`.
    /// Before one was saved, the default without the tiles that were turned off then.
    /// Entries that are no tile, a tile twice, and tiles past the fourth row are dropped.
    public var arrangement: [OverviewItem] {
        get {
            guard let saved = defaults.object(forKey: Key.arrangement) as? [String] else {
                let hidden = hiddenWidgets
                return OverviewGrid.defaultArrangement.filter { !hidden.contains($0.widget.rawValue) }
            }
            return OverviewGrid.arrangement(from: saved)
        }
        nonmutating set {
            defaults.set(OverviewGrid.entries(of: newValue), forKey: Key.arrangement)
        }
    }
}
