import Foundation

/// The countdowns under way, each with what it is for. Pure, like the countdown itself.
public struct TimerBoard: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public let id: Int
        public var label: String
        public var timer: CountdownTimer
    }

    /// How many countdowns can be kept at once: what fits on the page.
    public static let capacity = 4

    public private(set) var entries: [Entry] = []
    private var nextID = 1

    public init() {}

    public var isFull: Bool {
        entries.count >= Self.capacity
    }

    public var hasRunning: Bool {
        entries.contains { entry in
            if case .running = entry.timer.phase { return true }
            return false
        }
    }

    /// Starts a countdown and returns its number, or nil when there is no room.
    @discardableResult
    public mutating func add(duration: TimeInterval, label: String, at now: Date) -> Int? {
        guard !isFull else { return nil }
        var timer = CountdownTimer()
        timer.start(duration: duration, at: now)
        let id = nextID
        nextID += 1
        entries.append(Entry(id: id, label: label, timer: timer))
        return id
    }

    public mutating func pause(_ id: Int, at now: Date) {
        change(id) { $0.pause(at: now) }
    }

    public mutating func resume(_ id: Int, at now: Date) {
        change(id) { $0.resume(at: now) }
    }

    public mutating func extend(_ id: Int, by seconds: TimeInterval, at now: Date) {
        change(id) { $0.extend(by: seconds, at: now) }
    }

    public mutating func remove(_ id: Int) {
        entries.removeAll { $0.id == id }
    }

    /// The countdowns that ended since the last call, each reported once.
    public mutating func tick(at now: Date) -> [Entry] {
        var ended: [Entry] = []
        for index in entries.indices where entries[index].timer.tick(at: now) {
            ended.append(entries[index])
        }
        return ended
    }

    /// The running countdown with the least time left.
    public func soonest(at now: Date) -> Entry? {
        entries
            .filter { entry in
                if case .running = entry.timer.phase { return true }
                return false
            }
            .min { $0.timer.remaining(at: now) < $1.timer.remaining(at: now) }
    }

    private mutating func change(_ id: Int, _ body: (inout CountdownTimer) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        body(&entries[index].timer)
    }
}

/// The length chosen for a countdown, as its three wheels show it.
public struct TimerLength: Equatable, Sendable {
    public enum Wheel: Sendable {
        case hours, minutes, seconds
    }

    public static let range = 1...Int(CountdownTimer.durationRange.upperBound)

    public let total: Int

    public init(seconds: Int) {
        total = min(max(seconds, Self.range.lowerBound), Self.range.upperBound)
    }

    public var hours: Int { total / 3_600 }
    public var minutes: Int { (total % 3_600) / 60 }
    public var seconds: Int { total % 60 }

    /// The length in minutes when it has no seconds over, for the one-click choices.
    public var wholeMinutes: Int? {
        total >= 60 && total % 60 == 0 ? total / 60 : nil
    }

    /// One wheel turned by some steps. A wheel stops at the ends of its own range.
    public func turning(_ wheel: Wheel, by steps: Int) -> TimerLength {
        var hours = hours, minutes = minutes, seconds = seconds
        switch wheel {
        case .hours: hours = min(max(hours + steps, 0), Self.range.upperBound / 3_600)
        case .minutes: minutes = min(max(minutes + steps, 0), 59)
        case .seconds: seconds = min(max(seconds + steps, 0), 59)
        }
        return TimerLength(seconds: hours * 3_600 + minutes * 60 + seconds)
    }
}
