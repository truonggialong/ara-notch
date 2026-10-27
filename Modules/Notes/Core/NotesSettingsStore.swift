import Foundation

/// Reads and writes the Notes settings.
public struct NotesSettingsStore {
    public enum Key {
        public static let recentIDs = "notes.recentIDs"
        public static let selectedFolderID = "notes.selectedFolderID"
        public static let defaultFolderID = "notes.defaultFolderID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The notes opened last, newest first.
    public var recentIDs: [String] {
        get { defaults.stringArray(forKey: Key.recentIDs) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.recentIDs) }
    }

    /// The folder the list shows; nil for every folder.
    public var selectedFolderID: String? {
        get { defaults.string(forKey: Key.selectedFolderID) }
        nonmutating set { defaults.set(newValue, forKey: Key.selectedFolderID) }
    }

    /// Where new notes go; nil for the first folder.
    public var defaultFolderID: String? {
        get { defaults.string(forKey: Key.defaultFolderID) }
        nonmutating set { defaults.set(newValue, forKey: Key.defaultFolderID) }
    }
}
