import Foundation

/// Claude's rate limits as Claude Code tells them: asked in its control protocol
/// (`get_usage`, what `/usage` shows), so no keychain read is needed. Some accounts get
/// `rate_limits: null`, which is "no numbers", not an error.
public enum ClaudeCodeUsage {
    public enum Reply: Equatable, Sendable {
        case usage(AgentUsage)
        /// Claude Code answered without numbers for this account.
        case empty
    }

    /// The lines sent to Claude Code, each ended by a new line.
    public static let requests: [String] = [
        #"{"type":"control_request","request_id":"initialize","request":{"subtype":"initialize"}}"#,
        #"{"type":"control_request","request_id":"usage","request":{"subtype":"get_usage","skip_behaviors":true}}"#,
    ]

    /// Claude Code started with nothing of the user's: no tools, no MCP servers, no hooks,
    /// no settings, no session saved.
    public static let arguments: [String] = [
        "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--no-session-persistence", "--tools", "", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
        "--setting-sources", "", "--settings", #"{"disableAllHooks":true}"#,
    ]

    /// The environment Claude Code runs in: the app's, without what would make it think it
    /// runs inside another Claude Code or under another account, and without updating itself.
    public static func environment(_ base: [String: String]) -> [String: String] {
        var result = base.filter { key, _ in
            key != "CLAUDECODE" && !key.hasPrefix("CLAUDE_") && !key.hasPrefix("ANTHROPIC_")
        }
        result["DISABLE_AUTOUPDATER"] = "1"
        return result
    }

    /// One line of Claude Code's output: the reply to `get_usage`, or nil for any other line.
    public static func reply(fromLine line: Data, at date: Date) -> Reply? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "control_response",
              let response = object["response"] as? [String: Any],
              response["request_id"] as? String == "usage"
        else { return nil }
        guard response["subtype"] as? String == "success",
              let body = response["response"] as? [String: Any],
              body["rate_limits_available"] as? Bool != false,
              let limits = body["rate_limits"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: limits),
              let usage = ClaudeAccountUsage.usage(from: data, at: date)
        else { return .empty }
        return .usage(usage)
    }
}

/// The limits the Claude app saves as it checks them (every five to fifteen minutes), in
/// `plan-usage-history.json`: percentages only, without the time each window starts afresh.
public enum ClaudeAppUsage {
    /// A reading older than this has missed a check of the app: it is closed or stopped.
    public static let freshness: TimeInterval = 30 * 60
    static let maximumSize = 4 << 20

    public static func historyURL(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
    }

    /// The newest reading, when it is fresh. Version 1 keeps the numbers beside the time,
    /// version 2 under `u`; `fh` is the five hours, `sd` the seven days.
    public static func usage(from data: Data, now: Date) -> AgentUsage? {
        guard data.count <= maximumSize,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = (json["version"] as? NSNumber)?.intValue, version == 1 || version == 2,
              let samples = json["samples"] as? [[String: Any]]
        else { return nil }
        var newest: (date: Date, values: [String: Any])?
        for sample in samples {
            guard let milliseconds = (sample["t"] as? NSNumber)?.doubleValue, milliseconds.isFinite, milliseconds > 0
            else { continue }
            let date = Date(timeIntervalSince1970: milliseconds / 1000)
            let values = version == 1 ? sample : (sample["u"] as? [String: Any] ?? [:])
            if newest == nil || date > newest!.date { newest = (date, values) }
        }
        guard let newest, newest.date <= now.addingTimeInterval(300),
              now.timeIntervalSince(newest.date) < freshness
        else { return nil }
        func window(_ key: String) -> UsageWindow? {
            guard let number = newest.values[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue.isFinite
            else { return nil }
            return UsageWindow(usedPercent: min(100, max(0, number.doubleValue)), resetsAt: nil)
        }
        let fiveHour = window("fh"), sevenDay = window("sd")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return AgentUsage(fiveHour: fiveHour, sevenDay: sevenDay, updatedAt: newest.date)
    }
}
