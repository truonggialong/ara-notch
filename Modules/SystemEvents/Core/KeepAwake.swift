import Foundation

/// Keeping the Mac awake for a while, or until turned off. One click on the tool steps through
/// the lengths: off, 30 minutes, an hour, two hours, until turned off, and off again.
public struct KeepAwakeSession: Equatable, Sendable {
    /// What ends a session, besides the user.
    public enum Until: Equatable, Sendable {
        /// Its end time (`ends`), or nothing without one.
        case time
        /// The app with this bundle identifier quits.
        case app(bundleID: String, name: String)
        /// The files downloading now are done.
        case downloads
        /// A Trigger's condition stops being true; the id names the Trigger.
        case trigger(String)
    }

    /// When it ends; nil for a session without an end.
    public var ends: Date?
    /// How long it was set for; nil without an end.
    public var length: TimeInterval?
    public var until: Until

    public init(ends: Date?, length: TimeInterval? = nil, until: Until = .time) {
        self.ends = ends
        self.length = length
        self.until = until
    }

    /// Until a time of day: the next time the clock shows it, today or tomorrow.
    public static func until(minutesOfDay: Int, now: Date, calendar: Calendar = .current) -> KeepAwakeSession {
        let start = calendar.startOfDay(for: now)
        var end = calendar.date(byAdding: .minute, value: minutesOfDay, to: start) ?? now
        if end <= now { end = calendar.date(byAdding: .day, value: 1, to: end) ?? end }
        return KeepAwakeSession(ends: end, length: end.timeIntervalSince(now))
    }

    /// The same session, longer by `minutes`.
    public func extended(byMinutes minutes: Int, now: Date) -> KeepAwakeSession {
        var longer = self
        let base = max(ends ?? now, now)
        longer.ends = base.addingTimeInterval(TimeInterval(minutes * 60))
        longer.length = (length ?? 0) + TimeInterval(minutes * 60)
        return longer
    }

    /// How much of it is left, 0…1, for a ring that empties; a full ring without an end.
    public func remaining(at now: Date) -> Double {
        guard let ends, let length, length > 0 else { return 1 }
        return min(max(ends.timeIntervalSince(now) / length, 0), 1)
    }

    /// The lengths a click steps through, in minutes; nil is without an end.
    public static let steps: [Int?] = [30, 60, 120, nil]

    /// The session after a click: the next length from the one running, or off after the last.
    /// The length running is read from what is left, so a session started at an hour and now
    /// at 40 minutes goes on to two hours.
    public static func next(after current: KeepAwakeSession?, now: Date) -> KeepAwakeSession? {
        guard let current else {
            let length = TimeInterval(steps[0]! * 60)
            return KeepAwakeSession(ends: now.addingTimeInterval(length), length: length)
        }
        guard let ends = current.ends else { return nil }
        let left = ends.timeIntervalSince(now) / 60
        guard let index = steps.firstIndex(where: { $0.map { Double($0) >= left - 0.5 } ?? true }),
              index + 1 < steps.count
        else { return nil }
        let length = steps[index + 1].map { TimeInterval($0 * 60) }
        return KeepAwakeSession(ends: length.map { now.addingTimeInterval($0) }, length: length)
    }

    public func isOver(at now: Date) -> Bool {
        ends.map { $0 <= now } ?? false
    }

    /// "1:45" hours and minutes left, "29′" under an hour, "∞" without an end.
    public func left(at now: Date) -> String {
        guard let ends else { return "∞" }
        let minutes = max(0, Int((ends.timeIntervalSince(now) / 60).rounded(.up)))
        return minutes >= 60 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : "\(minutes)\u{2032}"
    }
}
