import Combine
import OverviewCore

/// The overview's arrangement, kept in the settings as it changes.
@MainActor
public final class OverviewSettings: ObservableObject {
    private let store: OverviewSettingsStore

    @Published public var arrangement: [OverviewItem] {
        didSet { store.arrangement = arrangement }
    }

    public init(store: OverviewSettingsStore) {
        self.store = store
        arrangement = store.arrangement
    }
}
