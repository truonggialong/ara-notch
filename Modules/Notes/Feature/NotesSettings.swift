import Combine
import NotesCore

/// Observable Notes settings; every change is written through to the store.
@MainActor
public final class NotesSettings: ObservableObject {
    private let store: NotesSettingsStore

    @Published public var recentIDs: [String] {
        didSet { store.recentIDs = recentIDs }
    }

    @Published public var selectedFolderID: String? {
        didSet { store.selectedFolderID = selectedFolderID }
    }

    @Published public var defaultFolderID: String? {
        didSet { store.defaultFolderID = defaultFolderID }
    }

    public init(store: NotesSettingsStore) {
        self.store = store
        recentIDs = store.recentIDs
        selectedFolderID = store.selectedFolderID
        defaultFolderID = store.defaultFolderID
    }
}
