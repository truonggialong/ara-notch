import CalendarCore
import Combine

/// Observable calendar settings; every change is written through to the store.
@MainActor
public final class CalendarSettings: ObservableObject {
    private let store: CalendarSettingsStore

    @Published public var meetingAlerts: Bool {
        didSet { store.meetingAlerts = meetingAlerts }
    }

    @Published public var leadMinutes: Int {
        didSet { store.leadMinutes = leadMinutes }
    }

    @Published public var showsLunarDate: Bool {
        didSet { store.showsLunarDate = showsLunarDate }
    }

    /// How many minutes each reminder's work is thought to take, by reminder.
    @Published public var estimates: [String: Int] {
        didSet { store.estimates = estimates }
    }

    public init(store: CalendarSettingsStore) {
        self.store = store
        estimates = store.estimates
        meetingAlerts = store.meetingAlerts
        leadMinutes = store.leadMinutes
        showsLunarDate = store.showsLunarDate
    }
}
