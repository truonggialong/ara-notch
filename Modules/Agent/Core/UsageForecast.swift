import Foundation

/// What is left of an agent's five-hour limit, and what the turn now starting is expected
/// to take from it, going by what recent turns took.
public struct UsageForecast: Equatable, Sendable {
    /// A number older than this is shown with the time it is from.
    public static let freshness: TimeInterval = 300
    /// Fewer measured turns than this say too little to estimate from.
    public static let minimumTurns = 3
    /// The estimate looks at this many of the latest turns.
    public static let turnsConsidered = 10

    /// 0…100, of the five-hour window as last reported.
    public let remainingPercent: Double
    /// What a turn is expected to take; nil while too few turns have been measured.
    public let estimatedCostPercent: Double?
    /// When the agent reported the number.
    public let asOf: Date

    /// - Parameters:
    ///   - usage: the agent's limits as last reported; nil when it never reported any. Nil
    ///     comes back too when the window reported on has ended since.
    ///   - costs: what earlier turns took, in percent of the window, oldest first.
    public init?(usage: AgentUsage?, costs: [Double], now: Date) {
        guard let usage, let window = usage.fiveHour else { return nil }
        // A number from a window that has ended says nothing of the one now running.
        if let resetsAt = window.resetsAt, resetsAt <= now { return nil }
        remainingPercent = min(max(100 - window.usedPercent, 0), 100)
        estimatedCostPercent = Self.estimate(from: costs)
        asOf = usage.updatedAt
    }

    /// What is expected to be left once the turn is done.
    public var expectedRemainingPercent: Double? {
        estimatedCostPercent.map { max(remainingPercent - $0, 0) }
    }

    /// True when the number is old enough that it may no longer hold: an agent that runs
    /// where it reports nothing leaves the last number standing for hours.
    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(asOf) > Self.freshness
    }

    /// The middle one of the latest turns, so that one costly turn does not carry the
    /// estimate away.
    public static func estimate(from costs: [Double]) -> Double? {
        let recent = costs.suffix(turnsConsidered).sorted()
        guard recent.count >= minimumTurns else { return nil }
        let middle = recent.count / 2
        return recent.count.isMultiple(of: 2) ? (recent[middle - 1] + recent[middle]) / 2 : recent[middle]
    }
}

/// Measures what turns take from the five-hour window: what the window stood at when a
/// turn began, and what it stood at when the turn ended. Approximate by nature: the agent
/// reports when it pleases, and only where it has a status line.
public struct TurnCostLedger: Equatable, Sendable {
    /// How many of the latest costs are kept.
    public static let capacity = 20

    private struct Start: Equatable, Sendable {
        var usedPercent: Double?
        var resetsAt: Date?
        var at: Date
        /// Another turn ran at the same time: what the window rose by is not this turn's alone.
        var isShared = false
    }

    /// What measured turns took, in percent of the window, oldest first.
    public private(set) var costs: [Double]
    private var open: [String: Start] = [:]

    public init(costs: [Double] = []) {
        self.costs = Array(costs.suffix(Self.capacity))
    }

    /// A turn began. The number is taken only when the agent reported it just now.
    public mutating func begin(sessionID: String, usage: AgentUsage?, at date: Date) {
        var start = Start(at: date)
        if let usage, let window = usage.fiveHour, date.timeIntervalSince(usage.updatedAt) <= UsageForecast.freshness {
            start.usedPercent = window.usedPercent
            start.resetsAt = window.resetsAt
        }
        if !open.isEmpty {
            start.isShared = true
            for id in open.keys {
                open[id]?.isShared = true
            }
        }
        open[sessionID] = start
    }

    /// The turn ended. Returns what it took when that can be told: a number from the start,
    /// a newer one since, the same window, and no other turn alongside.
    @discardableResult
    public mutating func end(sessionID: String, usage: AgentUsage?, at date: Date) -> Double? {
        guard let start = open.removeValue(forKey: sessionID), !start.isShared, let before = start.usedPercent,
              let usage, let window = usage.fiveHour, usage.updatedAt > start.at
        else { return nil }
        // The window started afresh while the turn ran.
        if let resetsAt = start.resetsAt, resetsAt <= date { return nil }
        let cost = window.usedPercent - before
        guard cost >= 0 else { return nil }
        costs = Array((costs + [cost]).suffix(Self.capacity))
        return cost
    }

    /// Forgets a turn whose end will not be seen, such as one of a session that closed.
    public mutating func forget(sessionID: String) {
        open[sessionID] = nil
    }
}
