import Foundation

/// Something a coding agent (Claude Code) reported through its hooks.
public struct AgentEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sessionStart = "SessionStart"
        case promptSubmit = "UserPromptSubmit"
        case toolUse = "PreToolUse"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"
    }

    public var kind: Kind
    public var sessionID: String
    /// The folder the agent works in.
    public var cwd: String?
    public var toolName: String?
    /// The agent's own notice, e.g. that it needs permission.
    public var message: String?
    /// Path of the app the agent runs in (a terminal, an editor), when the hook could tell.
    public var hostApp: String?
    public var at: Date

    public init(
        kind: Kind, sessionID: String, cwd: String?, toolName: String?, message: String?, hostApp: String? = nil, at: Date
    ) {
        self.hostApp = hostApp
        self.kind = kind
        self.sessionID = sessionID
        self.cwd = cwd
        self.toolName = toolName
        self.message = message
        self.at = at
    }
}

/// Reduces what a hook receives to the one line the app stores. Prompts, tool inputs and
/// transcript paths are dropped here, so they never reach the app's files.
public enum AgentHookInput {
    static let maxMessageLength = 200

    /// - Parameter input: the JSON Claude Code passes to a hook on standard input.
    /// - Returns: one line of JSON, or nil when the input is not a hook event this app follows.
    public static func compact(_ input: Data, at date: Date, hostApp: String? = nil) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
              let session = object["session_id"] as? String, !session.isEmpty,
              let name = object["hook_event_name"] as? String, AgentEvent.Kind(rawValue: name) != nil
        else { return nil }

        var line: [String: Any] = ["t": date.timeIntervalSince1970, "event": name, "session": session]
        if let cwd = object["cwd"] as? String, !cwd.isEmpty {
            line["cwd"] = cwd
        }
        if let tool = object["tool_name"] as? String, !tool.isEmpty {
            line["tool"] = tool
        }
        if let message = object["message"] as? String, !message.isEmpty {
            line["message"] = String(message.prefix(maxMessageLength))
        }
        if let hostApp, !hostApp.isEmpty {
            line["app"] = hostApp
        }
        guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

/// Reads the lines the hook helper wrote.
public enum AgentEventParser {
    public static func parse(line: String) -> AgentEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let kind = (object["event"] as? String).flatMap(AgentEvent.Kind.init),
              let session = object["session"] as? String, !session.isEmpty,
              let time = (object["t"] as? NSNumber)?.doubleValue
        else { return nil }
        return AgentEvent(
            kind: kind, sessionID: session, cwd: object["cwd"] as? String,
            toolName: object["tool"] as? String, message: object["message"] as? String,
            hostApp: object["app"] as? String, at: Date(timeIntervalSince1970: time))
    }
}

/// One agent session as shown on the notch.
public struct AgentSession: Equatable, Identifiable, Sendable {
    public enum State: Equatable, Sendable {
        /// Started, nothing asked yet.
        case idle
        case working(tool: String?)
        /// The agent asks for the user: a permission, or an answer.
        case waiting(message: String?)
        /// The agent finished its turn.
        case done
        /// The user stopped the turn midway; Claude Code reports no end for that.
        case stopped
    }

    public let id: String
    /// Name of the folder the agent works in.
    public var project: String
    public var cwd: String?
    /// Path of the app the agent runs in, for bringing that app forward.
    public var hostApp: String?
    public var state: State
    public var lastActivity: Date
}

extension AgentSession {
    /// Working on a request or waiting for the user in the middle of one.
    public var isMidTurn: Bool {
        switch state {
        case .working, .waiting: true
        case .idle, .done, .stopped: false
        }
    }

    /// The agent asks for the user.
    public var isWaitingForUser: Bool {
        if case .waiting = state { return true }
        return false
    }
}

/// A tool's name as people read it. An MCP tool comes as `mcp__server__tool`, snake case;
/// it is shown as "server › tool" in words.
public enum AgentToolName {
    public static func display(_ raw: String) -> String {
        let parts = raw.components(separatedBy: "__")
        guard parts.count >= 3, parts[0] == "mcp", !parts[1].isEmpty else { return raw }
        let words = { (part: String) in part.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ") }
        return "\(words(parts[1])) › \(words(parts.dropFirst(2).joined(separator: "__")))"
    }
}

/// Finding the app a command-line agent runs in.
public enum AgentHost {
    /// The app bundle among the executables of a process's ancestors, nearest first: the
    /// farthest one that lies inside an app, counted as the outermost app around it. The
    /// farthest, because an agent can be a bundle itself (Claude Code is) and a terminal can
    /// run its shells in helpers; the window the user sees belongs to the app at the top.
    public static func appPath(amongAncestors paths: [String]) -> String? {
        for path in paths.reversed() {
            guard let range = path.range(of: ".app/") else { continue }
            return String(path[..<range.lowerBound]) + ".app"
        }
        return nil
    }
}

/// The sessions currently known, built up from hook events.
public struct AgentSessions: Equatable, Sendable {
    /// What the user should be told beside the closed notch.
    public enum Announcement: Equatable, Sendable {
        /// A turn began: the agent set to work on a request.
        case started
        case needsAttention
        case finished
    }

    private var sessions: [String: AgentSession] = [:]

    public init() {}

    /// Those waiting for the user first, then the most recently active.
    public var list: [AgentSession] {
        sessions.values.sorted { first, second in
            let firstWaits = first.isWaitingForUser, secondWaits = second.isWaitingForUser
            if firstWaits != secondWaits { return firstWaits }
            return (first.lastActivity, first.id) > (second.lastActivity, second.id)
        }
    }

    public func session(id: String) -> AgentSession? {
        sessions[id]
    }

    /// Applies an event. Returns what to announce, if the session just set to work, began to
    /// wait for the user or finished; a repeat of the same state announces nothing.
    @discardableResult
    public mutating func apply(_ event: AgentEvent) -> Announcement? {
        if event.kind == .sessionEnd {
            sessions[event.sessionID] = nil
            return nil
        }
        // A session first seen midway (the app started later) is tracked from here on.
        var session = sessions[event.sessionID] ?? AgentSession(
            id: event.sessionID, project: "?", cwd: nil, state: .idle, lastActivity: event.at)
        if let cwd = event.cwd, !cwd.isEmpty {
            session.cwd = cwd
            session.project = URL(fileURLWithPath: cwd).lastPathComponent
        }
        session.lastActivity = event.at
        if let hostApp = event.hostApp, !hostApp.isEmpty {
            session.hostApp = hostApp
        }

        var announcement: Announcement?
        switch event.kind {
        case .sessionStart:
            session.state = .idle
        case .promptSubmit:
            // A request sent while the agent already works belongs to the turn under way.
            if case .working = session.state {} else {
                announcement = .started
            }
            session.state = .working(tool: nil)
        case .toolUse:
            session.state = .working(tool: event.toolName)
        case .notification:
            if case .waiting = session.state {} else {
                announcement = .needsAttention
            }
            session.state = .waiting(message: event.message)
        case .stop:
            if session.state != .done {
                announcement = .finished
            }
            session.state = .done
        case .sessionEnd:
            break
        }
        sessions[event.sessionID] = session
        return announcement
    }

    /// Forgets sessions with no activity since `date`; a session whose end was never reported
    /// would otherwise stay forever. Those in `keeping`, still open in a running Claude Code,
    /// stay however long they have been quiet.
    public mutating func expire(before date: Date, keeping open: Set<String> = []) {
        sessions = sessions.filter { $0.value.lastActivity >= date || open.contains($0.key) }
    }

    /// The turn of a working or waiting session was stopped by the user.
    public mutating func markStopped(id: String) {
        guard var session = sessions[id], session.isMidTurn else { return }
        session.state = .stopped
        sessions[id] = session
    }

    /// Turns with no sign of life since `date` are taken as stopped: a turn that goes on
    /// reports every tool it uses.
    public mutating func stopTurns(quietSince date: Date) {
        for (id, session) in sessions where session.isMidTurn && session.lastActivity < date {
            markStopped(id: id)
        }
    }
}

/// How a Claude Code session's transcript ends: whether the user stopped the last turn.
/// Only the last lines are given, and only what kind of line each is and whether the user's
/// line is the interrupt mark is looked at.
public enum TranscriptEnding {
    static let interruptMark = "[Request interrupted by user"

    public static func wasInterrupted(lastLines: [String]) -> Bool {
        for line in lastLines.reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String, type == "user" || type == "assistant"
            else { continue }
            guard type == "user" else { return false }
            let content = (object["message"] as? [String: Any])?["content"]
            let texts: [String]
            if let text = content as? String {
                texts = [text]
            } else {
                texts = (content as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
            }
            return texts.contains { $0.hasPrefix(interruptMark) }
        }
        return false
    }
}

/// The sessions open in a running Claude Code, read from the command lines of its processes:
/// the desktop app starts each one with `--resume=<session id>`.
public enum RunningClaudeSessions {
    private static let pattern = try! NSRegularExpression(
        pattern: #"--(?:resume|session-id)[= ]([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"#)

    public static func ids(fromCommands commands: [String]) -> Set<String> {
        var ids = Set<String>()
        for command in commands {
            // The program is what comes before the first option; its path may hold spaces.
            let program = command.components(separatedBy: " -").first ?? command
            guard (program as NSString).lastPathComponent == "claude" else { continue }
            let range = NSRange(command.startIndex..., in: command)
            for match in pattern.matches(in: command, range: range) {
                if let id = Range(match.range(at: 1), in: command) { ids.insert(String(command[id])) }
            }
        }
        return ids
    }
}
