/// The power state of the Mac at one moment.
public struct PowerSnapshot: Equatable, Sendable {
    /// False on a desktop Mac; such snapshots never produce events.
    public var hasBattery: Bool
    public var isOnAC: Bool
    public var isCharging: Bool
    /// 0…100.
    public var percent: Int
    /// Minutes until the battery is empty, or full while charging; nil while the system has
    /// not worked it out.
    public var minutesLeft: Int?

    public init(hasBattery: Bool = true, isOnAC: Bool, isCharging: Bool, percent: Int) {
        self.hasBattery = hasBattery
        self.isOnAC = isOnAC
        self.isCharging = isCharging
        self.percent = percent
    }
}

public enum PowerEvent: Equatable, Sendable {
    case pluggedIn(percent: Int)
    case unplugged(percent: Int)
    case low(percent: Int)
    case full
}

/// Turns successive power snapshots into the events worth telling the user about.
public struct PowerEventDetector: Sendable {
    /// Battery levels that trigger a low-battery alert, each once per discharge.
    public static let lowThresholds = [20, 10]

    private var previous: PowerSnapshot?
    private var alertedThresholds: Set<Int> = []
    private var hasAlertedFull = false

    public init() {}

    public mutating func update(_ snapshot: PowerSnapshot) -> [PowerEvent] {
        defer { previous = snapshot }
        guard snapshot.hasBattery else { return [] }

        var events: [PowerEvent] = []
        if let previous, previous.hasBattery {
            if !previous.isOnAC, snapshot.isOnAC {
                events.append(.pluggedIn(percent: snapshot.percent))
                alertedThresholds = []
                hasAlertedFull = false
            } else if previous.isOnAC, !snapshot.isOnAC {
                events.append(.unplugged(percent: snapshot.percent))
                hasAlertedFull = false
            }
        } else if snapshot.isOnAC, snapshot.percent >= 100 {
            // Already full at launch: nothing new to report.
            hasAlertedFull = true
        }

        if snapshot.isOnAC {
            if snapshot.percent >= 100, !hasAlertedFull {
                hasAlertedFull = true
                events.append(.full)
            }
        } else {
            // Several thresholds crossed at once still give a single alert.
            let crossed = Self.lowThresholds.filter { snapshot.percent <= $0 && !alertedThresholds.contains($0) }
            if !crossed.isEmpty {
                alertedThresholds.formUnion(crossed)
                events.append(.low(percent: snapshot.percent))
            }
        }
        return events
    }
}

/// How the time a battery has left is written.
public enum BatteryTime {
    /// "4:05" for 245 minutes; nil when the time is not known.
    public static func clock(minutes: Int?) -> String? {
        guard let minutes, minutes > 0 else { return nil }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}
