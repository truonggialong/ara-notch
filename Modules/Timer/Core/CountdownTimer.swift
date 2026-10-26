import Foundation

/// A single countdown. Pure: the caller supplies the current time and calls `tick` regularly.
public struct CountdownTimer: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        /// Reached zero; stays here until started again or cancelled.
        case finished
    }

    public static let durationRange: ClosedRange<TimeInterval> = 1...10_800

    public private(set) var phase: Phase = .idle
    /// Total length of the current countdown.
    public private(set) var duration: TimeInterval = 0

    public init() {}

    /// Starts a countdown from any state, replacing one that is under way.
    public mutating func start(duration: TimeInterval, at now: Date) {
        let clamped = duration.isNaN
            ? Self.durationRange.lowerBound
            : min(max(duration, Self.durationRange.lowerBound), Self.durationRange.upperBound)
        self.duration = clamped
        phase = .running(endsAt: now.addingTimeInterval(clamped))
    }

    public mutating func pause(at now: Date) {
        guard case .running = phase else { return }
        phase = .paused(remaining: remaining(at: now))
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let remaining) = phase else { return }
        phase = .running(endsAt: now.addingTimeInterval(remaining))
    }

    /// Adds time to a countdown under way, up to the longest one allowed.
    public mutating func extend(by seconds: TimeInterval, at now: Date) {
        let room = Self.durationRange.upperBound - remaining(at: now)
        let added = min(max(seconds, 0), max(room, 0))
        switch phase {
        case .running(let endsAt):
            phase = .running(endsAt: endsAt.addingTimeInterval(added))
        case .paused(let remaining):
            phase = .paused(remaining: remaining + added)
        case .idle, .finished:
            return
        }
        duration += added
    }

    public mutating func cancel() {
        phase = .idle
        duration = 0
    }

    /// Returns true exactly once: on the first call at or after the end time.
    public mutating func tick(at now: Date) -> Bool {
        guard case .running(let endsAt) = phase, now >= endsAt else { return false }
        phase = .finished
        return true
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch phase {
        case .idle, .finished: return 0
        case .running(let endsAt): return max(endsAt.timeIntervalSince(now), 0)
        case .paused(let remaining): return remaining
        }
    }

    /// The elapsed share of the countdown, 0…1.
    public func progress(at now: Date) -> Double {
        switch phase {
        case .idle: return 0
        case .finished: return 1
        case .running, .paused:
            guard duration > 0 else { return 0 }
            return min(max(1 - remaining(at: now) / duration, 0), 1)
        }
    }
}
