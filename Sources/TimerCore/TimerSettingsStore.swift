import Foundation

/// Reads and writes the timer settings. Missing, mistyped or out-of-range values fall back safely.
public struct TimerSettingsStore {
    public enum Key {
        public static let minutes = "timer.minutes"
        public static let sound = "timer.sound"
        public static let presets = "timer.presets"
        public static let label = "timer.label"
        public static let seconds = "timer.seconds"
    }

    public static let minutesRange: ClosedRange<Int> = 1...180
    public static let defaultMinutes = 25
    public static let defaultPresets = [5, 15, 25, 45]
    public static let maxPresets = 6
    public static let maxLabelLength = 40

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The length last chosen for a countdown.
    public var minutes: Int {
        get {
            guard let value = defaults.object(forKey: Key.minutes) as? Int else { return Self.defaultMinutes }
            return Self.clamp(value)
        }
        nonmutating set { defaults.set(Self.clamp(newValue), forKey: Key.minutes) }
    }

    /// The length last chosen, to the second. Until one is chosen it is the minutes kept by
    /// earlier versions.
    public var seconds: Int {
        get {
            guard let value = defaults.object(forKey: Key.seconds) as? Int else { return minutes * 60 }
            return TimerLength(seconds: value).total
        }
        nonmutating set { defaults.set(TimerLength(seconds: newValue).total, forKey: Key.seconds) }
    }

    public var soundEnabled: Bool {
        get { defaults.object(forKey: Key.sound) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.sound) }
    }

    /// The lengths offered as one-click choices, shortest first.
    public var presets: [Int] {
        guard let stored = defaults.object(forKey: Key.presets) as? [Int] else { return Self.defaultPresets }
        let valid = Array(Set(stored.filter(Self.minutesRange.contains))).sorted().prefix(Self.maxPresets)
        return valid.isEmpty ? Self.defaultPresets : Array(valid)
    }

    /// Whether this length could be saved as a preset: in range, not there yet, and room left.
    public func canAddPreset(_ minutes: Int) -> Bool {
        let presets = presets
        return Self.minutesRange.contains(minutes) && !presets.contains(minutes) && presets.count < Self.maxPresets
    }

    @discardableResult
    public func addPreset(_ minutes: Int) -> Bool {
        guard canAddPreset(minutes) else { return false }
        defaults.set((presets + [minutes]).sorted(), forKey: Key.presets)
        return true
    }

    /// Removes a preset. The last one stays: the page always offers at least one.
    @discardableResult
    public func removePreset(_ minutes: Int) -> Bool {
        let presets = presets
        guard presets.count > 1, presets.contains(minutes) else { return false }
        defaults.set(presets.filter { $0 != minutes }, forKey: Key.presets)
        return true
    }

    /// What the countdown is for, shown with it and when it ends. Optional.
    public var label: String {
        get { defaults.string(forKey: Key.label) ?? "" }
        nonmutating set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(String(trimmed.prefix(Self.maxLabelLength)), forKey: Key.label)
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, minutesRange.lowerBound), minutesRange.upperBound)
    }
}
