import Foundation

/// Adds this app's hooks to a Claude Code settings document, and takes them out again.
/// Works on the decoded JSON; reading, backing up and writing the file is the caller's job.
public enum ClaudeHooksInstaller {
    /// The hook events the app follows.
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"]
    /// Events that carry a tool name and take a matcher.
    private static let toolEvents: Set<String> = ["PreToolUse"]
    /// Part of every command this app installs; how its own hooks are recognised.
    static let marker = "aranotch-hook"

    /// The shell command for a hook: quoted, silent, and successful even if the helper is gone,
    /// so a missing helper can never get in the agent's way.
    public static func command(forHelperAt path: String) -> String {
        "'\(path.replacingOccurrences(of: "'", with: "'\\''"))' 2>/dev/null || true"
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isOurs)
            }
        }
    }

    /// Adds one hook per event, after any hooks the user already has. An older install of this
    /// app's hooks is replaced, so installing twice equals installing once.
    public static func install(into settings: [String: Any], command: String) -> [String: Any] {
        var settings = uninstall(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if toolEvents.contains(event) {
                group["matcher"] = "*"
            }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        settings["hooks"] = hooks
        return settings
    }

    /// Removes this app's hooks and nothing else; sections left empty are removed too.
    public static func uninstall(from settings: [String: Any]) -> [String: Any] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return settings }
        var settings = settings
        var remaining: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else {
                remaining[event] = value
                continue
            }
            let kept = groups.compactMap { group -> [String: Any]? in
                guard let entries = group["hooks"] as? [[String: Any]] else { return group }
                let others = entries.filter { !isOurs($0) }
                if others.count == entries.count { return group }
                guard !others.isEmpty else { return nil }
                var group = group
                group["hooks"] = others
                return group
            }
            if !kept.isEmpty {
                remaining[event] = kept
            }
        }
        settings["hooks"] = remaining.isEmpty ? nil : remaining
        return settings
    }

    private static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) ?? false
    }
}

/// Reads and writes the agent settings.
public struct AgentSettingsStore {
    public enum Key {
        public static let announcesAttention = "agents.announcesAttention"
        public static let announcesFinished = "agents.announcesFinished"
        public static let tracksCodex = "agents.tracksCodex"
        public static let announcesWorking = "agents.announcesWorking"
        public static let turnCostsClaude = "agents.turnCosts.claude"
        public static let turnCostsCodex = "agents.turnCosts.codex"
        public static let readsClaudeAccount = "agents.readsClaudeAccount"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Tell the user beside the notch when an agent waits for them.
    public var announcesAttention: Bool {
        get { defaults.object(forKey: Key.announcesAttention) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.announcesAttention) }
    }

    /// Follow Codex sessions and rate limits by reading Codex's own session logs.
    public var tracksCodex: Bool {
        get { defaults.object(forKey: Key.tracksCodex) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.tracksCodex) }
    }

    /// Tell the user, in a notice under the notch, when an agent sets to work on a request.
    public var announcesWorking: Bool {
        get { defaults.object(forKey: Key.announcesWorking) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.announcesWorking) }
    }

    /// What measured turns took from the five-hour limit, in percent, oldest first: what the
    /// estimate for the next turn is made from.
    public func turnCosts(codex: Bool) -> [Double] {
        defaults.object(forKey: codex ? Key.turnCostsCodex : Key.turnCostsClaude) as? [Double] ?? []
    }

    public func setTurnCosts(_ costs: [Double], codex: Bool) {
        defaults.set(costs, forKey: codex ? Key.turnCostsCodex : Key.turnCostsClaude)
    }

    /// Ask the Claude account for its rate limits, with the sign-in Claude Code keeps in the
    /// keychain. Off until the user turns it on: macOS asks them to allow the keychain read.
    public var readsClaudeAccount: Bool {
        get { defaults.object(forKey: Key.readsClaudeAccount) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.readsClaudeAccount) }
    }

    /// Tell the user beside the notch when an agent finished its turn.
    public var announcesFinished: Bool {
        get { defaults.object(forKey: Key.announcesFinished) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.announcesFinished) }
    }
}
