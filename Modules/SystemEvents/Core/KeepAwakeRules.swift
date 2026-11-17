import Foundation

/// How keeping awake behaves, as the user set it in Settings: whether the display may sleep,
/// when a session stops on its own, the reminder before it ends, and the Triggers that start
/// one by themselves.
public struct KeepAwakeSettingsStore {
    public enum Key {
        public static let allowsDisplaySleep = "keepAwake.allowsDisplaySleep"
        public static let stopsOnLowBattery = "keepAwake.stopsOnLowBattery"
        public static let lowBatteryPercent = "keepAwake.lowBatteryPercent"
        public static let stopsWhenUnplugged = "keepAwake.stopsWhenUnplugged"
        public static let stopsOnSleep = "keepAwake.stopsOnSleep"
        public static let remindsBeforeEnd = "keepAwake.remindsBeforeEnd"
        public static let triggerApps = "keepAwake.trigger.apps"
        public static let triggerDocked = "keepAwake.trigger.docked"
        public static let triggerSchedule = "keepAwake.trigger.schedule"
        public static let scheduleDays = "keepAwake.trigger.days"
        public static let scheduleStart = "keepAwake.trigger.start"
        public static let scheduleEnd = "keepAwake.trigger.end"
    }

    public static let lowBatteryChoices = [10, 20, 30]

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    private func bool(_ key: String, _ standard: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? standard }
    private func int(_ key: String, _ standard: Int) -> Int { defaults.object(forKey: key) as? Int ?? standard }

    /// Keep the Mac working but let the display sleep.
    public var allowsDisplaySleep: Bool {
        get { bool(Key.allowsDisplaySleep, false) }
        nonmutating set { defaults.set(newValue, forKey: Key.allowsDisplaySleep) }
    }

    public var stopsOnLowBattery: Bool {
        get { bool(Key.stopsOnLowBattery, true) }
        nonmutating set { defaults.set(newValue, forKey: Key.stopsOnLowBattery) }
    }

    public var lowBatteryPercent: Int {
        get { int(Key.lowBatteryPercent, 20) }
        nonmutating set { defaults.set(newValue, forKey: Key.lowBatteryPercent) }
    }

    public var stopsWhenUnplugged: Bool {
        get { bool(Key.stopsWhenUnplugged, false) }
        nonmutating set { defaults.set(newValue, forKey: Key.stopsWhenUnplugged) }
    }

    /// Stop when the Mac is put to sleep anyway (the Apple menu, the lid).
    public var stopsOnSleep: Bool {
        get { bool(Key.stopsOnSleep, true) }
        nonmutating set { defaults.set(newValue, forKey: Key.stopsOnSleep) }
    }

    public var remindsBeforeEnd: Bool {
        get { bool(Key.remindsBeforeEnd, true) }
        nonmutating set { defaults.set(newValue, forKey: Key.remindsBeforeEnd) }
    }

    /// Apps that keep the Mac awake while they run, by bundle identifier.
    public var triggerApps: [String] {
        get { defaults.stringArray(forKey: Key.triggerApps) ?? [] }
        nonmutating set { defaults.set(newValue, forKey: Key.triggerApps) }
    }

    /// Keep awake while on power with an external display: working at a desk.
    public var triggerDocked: Bool {
        get { bool(Key.triggerDocked, false) }
        nonmutating set { defaults.set(newValue, forKey: Key.triggerDocked) }
    }

    public var triggerSchedule: Bool {
        get { bool(Key.triggerSchedule, false) }
        nonmutating set { defaults.set(newValue, forKey: Key.triggerSchedule) }
    }

    /// Weekdays of the schedule, 1 Sunday … 7 Saturday; Monday to Friday until set.
    public var scheduleDays: Set<Int> {
        get { Set((defaults.array(forKey: Key.scheduleDays) as? [Int]) ?? [2, 3, 4, 5, 6]) }
        nonmutating set { defaults.set(newValue.sorted(), forKey: Key.scheduleDays) }
    }

    /// Minutes after midnight.
    public var scheduleStart: Int {
        get { int(Key.scheduleStart, 9 * 60) }
        nonmutating set { defaults.set(newValue, forKey: Key.scheduleStart) }
    }

    public var scheduleEnd: Int {
        get { int(Key.scheduleEnd, 18 * 60) }
        nonmutating set { defaults.set(newValue, forKey: Key.scheduleEnd) }
    }
}

/// What the Mac looks like now, for the rules below.
public struct KeepAwakeConditions: Equatable, Sendable {
    public var batteryPercent: Int?
    public var isOnPower: Bool
    public var externalDisplays: Int
    public var runningApps: Set<String>
    public var downloading: Bool

    public init(batteryPercent: Int?, isOnPower: Bool, externalDisplays: Int, runningApps: Set<String>, downloading: Bool) {
        self.batteryPercent = batteryPercent
        self.isOnPower = isOnPower
        self.externalDisplays = externalDisplays
        self.runningApps = runningApps
        self.downloading = downloading
    }
}

/// When a session stops on its own, when it reminds, and when a Trigger wants one.
public enum KeepAwakeRules {
    public enum Stop: Equatable, Sendable {
        case timeUp, appQuit, downloadsDone, lowBattery(Int), unplugged
    }

    /// The settings that matter to the rules, read once.
    public struct Settings: Equatable, Sendable {
        public var stopsOnLowBattery: Bool
        public var lowBatteryPercent: Int
        public var stopsWhenUnplugged: Bool
        public var triggerApps: [String]
        public var triggerDocked: Bool
        public var triggerSchedule: Bool
        public var scheduleDays: Set<Int>
        public var scheduleStart: Int
        public var scheduleEnd: Int

        public init(
            stopsOnLowBattery: Bool = true, lowBatteryPercent: Int = 20, stopsWhenUnplugged: Bool = false,
            triggerApps: [String] = [], triggerDocked: Bool = false, triggerSchedule: Bool = false,
            scheduleDays: Set<Int> = [2, 3, 4, 5, 6], scheduleStart: Int = 540, scheduleEnd: Int = 1080
        ) {
            self.stopsOnLowBattery = stopsOnLowBattery
            self.lowBatteryPercent = lowBatteryPercent
            self.stopsWhenUnplugged = stopsWhenUnplugged
            self.triggerApps = triggerApps
            self.triggerDocked = triggerDocked
            self.triggerSchedule = triggerSchedule
            self.scheduleDays = scheduleDays
            self.scheduleStart = scheduleStart
            self.scheduleEnd = scheduleEnd
        }

        public init(_ store: KeepAwakeSettingsStore) {
            self.init(
                stopsOnLowBattery: store.stopsOnLowBattery, lowBatteryPercent: store.lowBatteryPercent,
                stopsWhenUnplugged: store.stopsWhenUnplugged, triggerApps: store.triggerApps,
                triggerDocked: store.triggerDocked, triggerSchedule: store.triggerSchedule,
                scheduleDays: store.scheduleDays, scheduleStart: store.scheduleStart, scheduleEnd: store.scheduleEnd)
        }
    }

    /// Why the session should stop now, or nil to go on. A Trigger's session stops when its
    /// Trigger stops wanting it (see `trigger`), not here; the battery rules apply to all.
    public static func stop(
        _ session: KeepAwakeSession, conditions: KeepAwakeConditions, settings: Settings, now: Date
    ) -> Stop? {
        if !conditions.isOnPower, settings.stopsOnLowBattery, let battery = conditions.batteryPercent,
           battery <= settings.lowBatteryPercent {
            return .lowBattery(battery)
        }
        if !conditions.isOnPower, settings.stopsWhenUnplugged { return .unplugged }
        switch session.until {
        case .time:
            return session.isOver(at: now) ? .timeUp : nil
        case let .app(bundleID, _):
            return conditions.runningApps.contains(bundleID) ? nil : .appQuit
        case .downloads:
            return conditions.downloading ? nil : .downloadsDone
        case .trigger:
            return nil
        }
    }

    /// When to remind that a session is about to end: five minutes before, for a session
    /// set for more than ten. Nil for one without an end.
    public static func reminder(for session: KeepAwakeSession) -> Date? {
        guard session.until == .time, let ends = session.ends, let length = session.length, length > 10 * 60 else {
            return nil
        }
        return ends.addingTimeInterval(-5 * 60)
    }

    /// The Trigger that wants the Mac kept awake now, by id, or nil when none does: an app in
    /// the list running, power with an external display, or the hours of the schedule. A low
    /// battery wants nothing.
    public static func trigger(conditions: KeepAwakeConditions, settings: Settings, now: Date, calendar: Calendar = .current) -> String? {
        if !conditions.isOnPower, settings.stopsOnLowBattery, let battery = conditions.batteryPercent,
           battery <= settings.lowBatteryPercent {
            return nil
        }
        if let app = settings.triggerApps.first(where: conditions.runningApps.contains) {
            return "app:\(app)"
        }
        if settings.triggerDocked, conditions.isOnPower, conditions.externalDisplays > 0 {
            return "docked"
        }
        if settings.triggerSchedule, settings.scheduleDays.contains(calendar.component(.weekday, from: now)) {
            let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            if minutes >= settings.scheduleStart, minutes < settings.scheduleEnd {
                return "schedule"
            }
        }
        return nil
    }
}
