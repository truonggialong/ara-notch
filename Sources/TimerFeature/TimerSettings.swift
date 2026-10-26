import Combine
import TimerCore

/// Observable timer settings; every change is written through to the store.
@MainActor
public final class TimerSettings: ObservableObject {
    private let store: TimerSettingsStore

    /// The length chosen for the next countdown, to the second.
    @Published public var seconds: Int {
        didSet {
            let length = TimerLength(seconds: seconds)
            guard length.total == seconds else {
                seconds = length.total
                return
            }
            store.seconds = seconds
            // Kept for the one-click choices, which are whole minutes.
            if let minutes = length.wholeMinutes, TimerSettingsStore.minutesRange.contains(minutes) {
                store.minutes = minutes
            }
        }
    }

    @Published public var soundEnabled: Bool {
        didSet { store.soundEnabled = soundEnabled }
    }

    @Published public private(set) var presets: [Int]

    /// What the next countdown is for. Written through as typed; the store trims and shortens it.
    @Published public var label: String {
        didSet { store.label = label }
    }

    public init(store: TimerSettingsStore) {
        self.store = store
        seconds = store.seconds
        soundEnabled = store.soundEnabled
        presets = store.presets
        label = store.label
    }

    public var length: TimerLength {
        TimerLength(seconds: seconds)
    }

    public func turn(_ wheel: TimerLength.Wheel, by steps: Int) {
        seconds = length.turning(wheel, by: steps).total
    }

    public var canAddCurrentAsPreset: Bool {
        length.wholeMinutes.map(store.canAddPreset) ?? false
    }

    public func addCurrentAsPreset() {
        guard let minutes = length.wholeMinutes else { return }
        store.addPreset(minutes)
        presets = store.presets
    }

    public func removePreset(_ minutes: Int) {
        store.removePreset(minutes)
        presets = store.presets
    }

    /// The label as the store keeps it: trimmed, and empty when there is none.
    public var trimmedLabel: String {
        store.label
    }
}
