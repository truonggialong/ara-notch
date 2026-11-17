import Foundation

/// Which finished turns are worth a notice: a turn of a few seconds is not news.
public enum FinishNotice {
    /// The choices for the shortest turn worth a notice, in seconds; 0 is every turn.
    public static let minimums: [TimeInterval] = [0, 30, 60, 120, 300]
    public static let standardMinimum: TimeInterval = 60

    /// Whether a turn that took `duration` is announced. A turn whose start is not known
    /// (it began before the app was watching) is announced, as before.
    public static func announces(duration: TimeInterval?, minimum: TimeInterval) -> Bool {
        guard let duration else { return true }
        return duration >= minimum
    }
}

/// Notices about the rate limits: once a window's use reaches the threshold the user chose,
/// and once a window starts afresh. Each warning is said once per window, however often the
/// limits are read again.
public struct LimitAlerts: Sendable {
    /// The choices for the warning threshold, in percent used; 0 is off.
    public static let thresholds: [Double] = [0, 50, 75, 80, 90, 95]
    public static let standardThreshold: Double = 80

    public enum Window: String, Sendable {
        case fiveHour, sevenDay
    }

    public enum Alert: Equatable, Sendable {
        case nearing(Window, percent: Double)
        case renewed(Window)
    }

    /// Windows already warned about, by window and the time it resets.
    private var warned: Set<String> = []
    /// When each window was last said to reset.
    private var resets: [Window: Date] = [:]

    public init() {}

    /// Takes a new reading of an agent's limits. `threshold` nil or 0 is no warnings.
    public mutating func update(_ usage: AgentUsage, threshold: Double?, now: Date) -> [Alert] {
        var alerts: [Alert] = []
        for (window, reading) in [(Window.fiveHour, usage.fiveHour), (.sevenDay, usage.sevenDay)] {
            guard let reading else { continue }
            if let resetsAt = reading.resetsAt {
                // The reset time moved on past one that has come: the window started afresh.
                if let previous = resets[window], previous <= now, resetsAt.timeIntervalSince(previous) > 60 {
                    alerts.append(.renewed(window))
                }
                resets[window] = resetsAt
            }
            let key = "\(window.rawValue)|\(reading.resetsAt?.timeIntervalSince1970 ?? 0)"
            if let threshold, threshold > 0, reading.usedPercent >= threshold, !warned.contains(key) {
                warned.insert(key)
                alerts.append(.nearing(window, percent: reading.usedPercent))
            }
        }
        return alerts
    }
}

/// What rests beside the closed notch while agents work: how long the oldest turn has run, the
/// limit used, or nothing.
public enum AgentLiveReadout: String, CaseIterable, Sendable {
    case elapsed, limit, off

    public static let standard = AgentLiveReadout.elapsed

    /// "0:42", "12:05", "1:02:05": a stopwatch.
    public static func stopwatch(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
