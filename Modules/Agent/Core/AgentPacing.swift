import Foundation

/// How often the agent page looks at things outside the app: the list of running processes,
/// Codex logs held open, the Claude account. Each is looked at only while it can tell something
/// new, so a Mac with no agent at work is left alone.
public enum AgentPacing {
    // MARK: Running Claude Code sessions

    /// The process list says which sessions a running Claude Code still has open. It decides
    /// only when a session is forgotten, after hours of quiet, so a reading this old will do.
    public static let processListInterval: TimeInterval = 120

    /// Whether to read the process list now: only with Claude sessions on the page, and not
    /// again within `processListInterval`.
    public static func readsProcessList(claudeSessions: Int, lastRead: Date?, now: Date) -> Bool {
        guard claudeSessions > 0 else { return false }
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= processListInterval
    }

    // MARK: Codex logs held open

    /// The system reports a log only as it is closed, and Codex keeps its log open for the
    /// whole session; logs written this recently are read again every `openLogPoll` seconds.
    public static let openLogWindow: TimeInterval = 30 * 60
    public static let openLogPoll: TimeInterval = 2

    /// The logs to read again now: those written within `openLogWindow`.
    public static func openLogs(_ lastWrites: [String: Date], now: Date) -> [String] {
        lastWrites.filter { now.timeIntervalSince($0.value) < openLogWindow }.map(\.key).sorted()
    }

    // MARK: The Claude account

    /// While the agent page shows, the limits are asked for this often; otherwise less often.
    public static let accountWhileShown: TimeInterval = 60
    public static let accountWhileHidden: TimeInterval = 300
    /// After a failed check the next waits longer each time, up to this.
    public static let accountLongestWait: TimeInterval = 30 * 60

    /// How long to wait before the next account check. `failures` counts failed checks in a
    /// row: 0 after a good one.
    public static func accountDelay(pageShown: Bool, failures: Int) -> TimeInterval {
        let usual = pageShown ? accountWhileShown : accountWhileHidden
        guard failures > 0 else { return usual }
        let doubled = accountWhileHidden * pow(2, Double(min(failures, 8) - 1))
        return min(max(doubled, usual), accountLongestWait)
    }

    /// Whether a reading this old is stale enough to ask again as the page comes into view.
    public static func accountIsStale(lastRead: Date?, now: Date) -> Bool {
        guard let lastRead else { return true }
        return now.timeIntervalSince(lastRead) >= accountWhileShown
    }
}
