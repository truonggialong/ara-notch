import Foundation

/// Which system alerts appear on the notch. All are on unless switched off.
public struct AlertSettingsStore {
    public enum Key {
        public static let power = "alerts.power"
        public static let capsLock = "alerts.capsLock"
        public static let network = "alerts.network"
        public static let bluetooth = "alerts.bluetooth"
        public static let replacesHUD = "alerts.replacesHUD"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var power: Bool {
        get { bool(Key.power) }
        nonmutating set { defaults.set(newValue, forKey: Key.power) }
    }

    public var capsLock: Bool {
        get { bool(Key.capsLock) }
        nonmutating set { defaults.set(newValue, forKey: Key.capsLock) }
    }

    public var network: Bool {
        get { bool(Key.network) }
        nonmutating set { defaults.set(newValue, forKey: Key.network) }
    }

    public var bluetooth: Bool {
        get { bool(Key.bluetooth) }
        nonmutating set { defaults.set(newValue, forKey: Key.bluetooth) }
    }

    /// Show volume and brightness on the notch instead of the system's own display. Off unless
    /// switched on: it takes over the volume and brightness keys and needs Accessibility.
    public var replacesHUD: Bool {
        get { defaults.object(forKey: Key.replacesHUD) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.replacesHUD) }
    }

    /// Missing or mistyped values count as on.
    private func bool(_ key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
