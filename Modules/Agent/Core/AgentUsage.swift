import Foundation

/// How much of one rate limit window is used up.
public struct UsageWindow: Equatable, Sendable {
    /// 0…100; above 100 once a limit is exceeded.
    public var usedPercent: Double
    /// When the window starts afresh.
    public var resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date?) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }

    /// The window as it stands at a moment; nil once it has reset since it was reported, as
    /// what was used after the reset is not known.
    public func current(at now: Date) -> UsageWindow? {
        guard let resetsAt, resetsAt <= now else { return self }
        return nil
    }
}

/// An agent's rate limits as last reported: the five-hour window and the weekly one.
public struct AgentUsage: Equatable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?
    public var updatedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?, updatedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.updatedAt = updatedAt
    }

    /// Reported more than a week ago: even the weekly window has started afresh since, so
    /// the agent has not been used in a while.
    public func isOld(at now: Date) -> Bool {
        now.timeIntervalSince(updatedAt) > 7 * 86_400
    }

    /// The more recent of two reports, from wherever they came.
    public static func latest(_ a: AgentUsage?, _ b: AgentUsage?) -> AgentUsage? {
        guard let a else { return b }
        guard let b else { return a }
        return b.updatedAt > a.updatedAt ? b : a
    }

    /// One line of JSON holding the numbers and nothing else, for the file the app watches.
    public var record: String? {
        func window(_ window: UsageWindow?) -> [String: Any]? {
            guard let window else { return nil }
            var object: [String: Any] = ["used": window.usedPercent]
            if let resetsAt = window.resetsAt {
                object["resets"] = resetsAt.timeIntervalSince1970
            }
            return object
        }
        var object: [String: Any] = ["t": updatedAt.timeIntervalSince1970]
        object["five_hour"] = window(fiveHour)
        object["seven_day"] = window(sevenDay)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    public init?(record: String) {
        guard let object = try? JSONSerialization.jsonObject(with: Data(record.utf8)) as? [String: Any],
              let time = (object["t"] as? NSNumber)?.doubleValue
        else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let value = object[key] as? [String: Any], let used = (value["used"] as? NSNumber)?.doubleValue
            else { return nil }
            return UsageWindow(
                usedPercent: used,
                resetsAt: (value["resets"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
        }
        let fiveHour = window("five_hour"), sevenDay = window("seven_day")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        self.init(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: Date(timeIntervalSince1970: time))
    }
}

/// Reads what Claude Code hands its status line command on standard input. The rate limits
/// are only given there, to Pro and Max subscribers, after a session's first reply.
public enum ClaudeStatusInput {
    public static func usage(from input: Data, at date: Date) -> AgentUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let limits = object["rate_limits"] as? [String: Any]
        else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let value = limits[key] as? [String: Any],
                  let used = (value["used_percentage"] as? NSNumber)?.doubleValue
            else { return nil }
            return UsageWindow(
                usedPercent: used,
                resetsAt: (value["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
        }
        let fiveHour = window("five_hour"), sevenDay = window("seven_day")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return AgentUsage(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: date)
    }

    public static func modelName(from input: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any]
        return (object?["model"] as? [String: Any])?["display_name"] as? String
    }
}

/// Reads the answer of the Claude account's usage address (`/api/oauth/usage`), the one
/// Claude Code's `/usage` reads: each window's use in whole percent and when it resets.
public enum ClaudeAccountUsage {
    public static let address = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func usage(from data: Data, at date: Date) -> AgentUsage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let value = object[key] as? [String: Any],
                  let used = (value["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            return UsageWindow(usedPercent: used, resetsAt: (value["resets_at"] as? String).flatMap(time(from:)))
        }
        let fiveHour = window("five_hour"), sevenDay = window("seven_day")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return AgentUsage(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: date)
    }

    /// "2026-10-18T19:30:00.661633+00:00" or "2026-10-23T06:00:00Z": the fraction, of any
    /// length, is read apart, as the system's reader takes at most three digits.
    static func time(from text: String) -> Date? {
        var whole = text, fraction = 0.0
        if let dot = text.firstIndex(of: "."),
           let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            fraction = Double("0" + text[dot..<end]) ?? 0
            whole = String(text[..<dot] + text[end...])
        }
        return ISO8601DateFormatter().date(from: whole).map { $0.addingTimeInterval(fraction) }
    }
}

/// What Claude Code keeps of its sign-in in the keychain ("Claude Code-credentials"): only
/// the access token and when it expires are read; the token is never stored or shown.
public enum ClaudeLogin: Equatable, Sendable {
    case valid(accessToken: String)
    /// Claude Code renews it the next time it runs; this app never does.
    case expired

    public static let keychainService = "Claude Code-credentials"

    public static func read(_ data: Data, now: Date) -> ClaudeLogin? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = object["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        if let expires = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: expires / 1000) <= now {
            return .expired
        }
        return .valid(accessToken: token)
    }
}

/// What the status line command prints, so the line it installs is of use in Claude Code too.
public enum ClaudeStatusLine {
    public static func text(usage: AgentUsage?, modelName: String?) -> String {
        var parts: [String] = []
        if let modelName, !modelName.isEmpty {
            parts.append(modelName)
        }
        if let window = usage?.fiveHour {
            parts.append("5h \(Int(window.usedPercent.rounded()))%")
        }
        if let window = usage?.sevenDay {
            parts.append("7d \(Int(window.usedPercent.rounded()))%")
        }
        return parts.joined(separator: " · ")
    }
}

/// Puts this app's status line command into a Claude Code settings document and takes it out
/// again. Claude Code has one status line; one the user set up themselves is never replaced.
public enum ClaudeStatusLineInstaller {
    public enum State: Equatable, Sendable {
        case absent
        case installed
        /// The user has a status line of their own.
        case foreign
    }

    /// Part of the command this app installs; how its own status line is recognised.
    static let marker = "aranotch-hook"

    /// Quoted, silent, and successful even if the helper is gone.
    public static func command(forHelperAt path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))' --statusline 2>/dev/null || true"
    }

    public static func state(of settings: [String: Any]) -> State {
        guard let line = settings["statusLine"] else { return .absent }
        let command = (line as? [String: Any])?["command"] as? String
        return command?.contains(marker) == true ? .installed : .foreign
    }

    /// Nil when the user already has a status line of their own.
    public static func install(into settings: [String: Any], command: String) -> [String: Any]? {
        guard state(of: settings) != .foreign else { return nil }
        var settings = settings
        settings["statusLine"] = ["type": "command", "command": command]
        return settings
    }

    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        guard state(of: settings) == .installed else { return settings }
        var settings = settings
        settings["statusLine"] = nil
        return settings
    }
}

/// Something read from a Codex session log (`~/.codex/sessions/…/rollout-….jsonl`).
public enum CodexRolloutEvent: Equatable, Sendable {
    case session(id: String, cwd: String?, at: Date)
    case taskStarted(at: Date)
    /// The turn completed or was aborted.
    case taskEnded(at: Date)
    case usage(AgentUsage)

    /// The same thing as an agent event, so Codex sessions sit in the list with the others.
    /// Their ids carry a prefix, which keeps them apart from Claude Code's.
    public static func agentEvent(for event: CodexRolloutEvent, sessionID: String) -> AgentEvent? {
        let id = AgentSession.codexPrefix + sessionID
        switch event {
        case .session(_, let cwd, let at):
            return AgentEvent(kind: .sessionStart, sessionID: id, cwd: cwd, toolName: nil, message: nil, at: at)
        case .taskStarted(let at):
            return AgentEvent(kind: .promptSubmit, sessionID: id, cwd: nil, toolName: nil, message: nil, at: at)
        case .taskEnded(let at):
            return AgentEvent(kind: .stop, sessionID: id, cwd: nil, toolName: nil, message: nil, at: at)
        case .usage:
            return nil
        }
    }
}

extension AgentSession {
    static let codexPrefix = "codex:"

    /// Whether this is a Codex session rather than a Claude Code one.
    public var isCodex: Bool { id.hasPrefix(Self.codexPrefix) }
}

/// Reads the lines of a Codex session log that say how the session is doing. Messages, tool
/// calls and their output are skipped without being looked at.
public enum CodexRolloutParser {
    private static let markers = ["session_meta", "task_started", "task_complete", "turn_aborted", "token_count"]

    private static let markerBytes = markers.map { Data("\"\($0)\"".utf8) }

    /// A cheap test, so the long lines that hold conversation content are never decoded.
    public static func mayMatter(_ line: String) -> Bool {
        markers.contains { line.contains("\"\($0)\"") }
    }

    /// The same test on the raw bytes of a line, before it is made into text at all.
    public static func mayMatter(bytes line: Data) -> Bool {
        markerBytes.contains { line.range(of: $0) != nil }
    }

    public static func parse(line: String) -> CodexRolloutEvent? {
        guard mayMatter(line),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any],
              let at = (object["timestamp"] as? String).flatMap(date(from:))
        else { return nil }

        if type == "session_meta" {
            guard let id = (payload["id"] ?? payload["session_id"]) as? String, !id.isEmpty else { return nil }
            return .session(id: id, cwd: payload["cwd"] as? String, at: at)
        }
        guard type == "event_msg" else { return nil }
        switch payload["type"] as? String {
        case "task_started":
            return .taskStarted(at: at)
        case "task_complete", "turn_aborted":
            return .taskEnded(at: at)
        case "token_count":
            guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
            func window(_ key: String) -> UsageWindow? {
                guard let value = limits[key] as? [String: Any],
                      let used = (value["used_percent"] as? NSNumber)?.doubleValue
                else { return nil }
                return UsageWindow(
                    usedPercent: used,
                    resetsAt: (value["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
            }
            // Codex calls them primary and secondary: the five-hour window and the weekly one.
            let fiveHour = window("primary"), sevenDay = window("secondary")
            guard fiveHour != nil || sevenDay != nil else { return nil }
            return .usage(AgentUsage(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: at))
        default:
            return nil
        }
    }

    /// "2026-10-07T01:15:31.250Z", with or without the fraction.
    private static func date(from text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
