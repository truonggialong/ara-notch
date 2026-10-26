import Foundation
import Testing
@testable import AgentCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func json(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Suite struct AgentHookInputTests {
    @Test func keepsOnlyWhatTheNotchNeeds() throws {
        let input = #"{"session_id":"abc","transcript_path":"/x/t.jsonl","cwd":"/Users/me/Dự án/app","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa"}}"#
        let line = try #require(AgentHookInput.compact(Data(input.utf8), at: date(100)))
        #expect(!line.contains("\n"))
        #expect(!line.contains("id_rsa"))
        #expect(!line.contains("transcript"))
        let object = try json(line)
        #expect(object["event"] as? String == "PreToolUse")
        #expect(object["session"] as? String == "abc")
        #expect(object["cwd"] as? String == "/Users/me/Dự án/app")
        #expect(object["tool"] as? String == "Bash")
        #expect(object["t"] as? Double == 100)
    }

    @Test func neverCarriesThePromptText() throws {
        let input = #"{"session_id":"abc","cwd":"/p","hook_event_name":"UserPromptSubmit","prompt":"mật khẩu của tôi là 1234"}"#
        let line = try #require(AgentHookInput.compact(Data(input.utf8), at: date(1)))
        #expect(!line.contains("1234"))
        #expect(!line.contains("prompt"))
    }

    @Test func keepsTheNotificationMessageShortened() throws {
        let long = String(repeating: "x", count: 500)
        let input = #"{"session_id":"abc","cwd":"/p","hook_event_name":"Notification","message":"\#(long)"}"#
        let line = try #require(AgentHookInput.compact(Data(input.utf8), at: date(1)))
        #expect((try json(line)["message"] as? String)?.count == 200)
    }

    @Test(arguments: ["", "không phải json", "[1]", #"{"cwd":"/p"}"#, #"{"session_id":"a","hook_event_name":"Bịa"}"#])
    func ignoresInputItCannotUse(_ input: String) {
        #expect(AgentHookInput.compact(Data(input.utf8), at: date(1)) == nil)
    }
}

@Suite struct AgentEventParserTests {
    @Test func readsBackWhatTheHookWrote() throws {
        let input = #"{"session_id":"abc","cwd":"/Users/me/app","hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#
        let line = try #require(AgentHookInput.compact(Data(input.utf8), at: date(50)))
        #expect(AgentEventParser.parse(line: line) == AgentEvent(
            kind: .notification, sessionID: "abc", cwd: "/Users/me/app", toolName: nil,
            message: "Claude needs your permission to use Bash", at: date(50)))
    }

    @Test(arguments: ["", "{", #"{"event":"Stop"}"#, #"{"event":"Nope","session":"a","t":1}"#])
    func ignoresBrokenLines(_ line: String) {
        #expect(AgentEventParser.parse(line: line) == nil)
    }
}

@Suite struct AgentSessionsTests {
    private func event(_ kind: AgentEvent.Kind, _ id: String = "s1", cwd: String? = "/Users/me/Dự án/web",
                       tool: String? = nil, message: String? = nil, at seconds: TimeInterval) -> AgentEvent {
        AgentEvent(kind: kind, sessionID: id, cwd: cwd, toolName: tool, message: message, at: date(seconds))
    }

    @Test func aSessionGoesThroughItsStates() {
        var sessions = AgentSessions()
        #expect(sessions.apply(event(.sessionStart, at: 1)) == nil)
        #expect(sessions.list.map(\.state) == [.idle])
        #expect(sessions.list[0].project == "web")

        // A turn that begins is announced (0.13.0).
        #expect(sessions.apply(event(.promptSubmit, at: 2)) == .started)
        #expect(sessions.list[0].state == .working(tool: nil))
        #expect(sessions.apply(event(.toolUse, tool: "Bash", at: 3)) == nil)
        #expect(sessions.list[0].state == .working(tool: "Bash"))

        #expect(sessions.apply(event(.notification, message: "cần quyền", at: 4)) == .needsAttention)
        #expect(sessions.list[0].state == .waiting(message: "cần quyền"))
        #expect(sessions.apply(event(.toolUse, tool: "Edit", at: 5)) == nil)

        #expect(sessions.apply(event(.stop, at: 6)) == .finished)
        #expect(sessions.list[0].state == .done)
        #expect(sessions.list[0].lastActivity == date(6))

        #expect(sessions.apply(event(.sessionEnd, at: 7)) == nil)
        #expect(sessions.list.isEmpty)
    }

    @Test func aSessionWaitingForTheUserIsListedFirst() {
        var sessions = AgentSessions()
        _ = sessions.apply(event(.promptSubmit, "waits", cwd: "/a", at: 1))
        _ = sessions.apply(event(.notification, "waits", cwd: "/a", message: "cần quyền", at: 2))
        _ = sessions.apply(event(.promptSubmit, "works", cwd: "/b", at: 3))
        _ = sessions.apply(event(.stop, "done", cwd: "/c", at: 4))
        #expect(sessions.list.map(\.id) == ["waits", "done", "works"])
    }

    @Test(arguments: [
        ("Bash", "Bash"),
        ("mcp__github__create_issue", "github › create issue"),
        ("mcp__very_long_server_name__very_long_tool_name_for_testing", "very long server name › very long tool name for testing"),
        ("mcp__broken", "mcp__broken"),
    ])
    func aToolIsNamedForPeople(_ raw: String, _ shown: String) {
        #expect(AgentToolName.display(raw) == shown)
    }

    @Test func aSessionFirstSeenMidwayIsStillTracked() {
        var sessions = AgentSessions()
        sessions.apply(event(.toolUse, "late", tool: "Read", at: 10))
        #expect(sessions.list.map(\.id) == ["late"])
        #expect(sessions.list[0].state == .working(tool: "Read"))
    }

    @Test func repeatedNoticesAnnounceOnlyOnce() {
        var sessions = AgentSessions()
        #expect(sessions.apply(event(.notification, message: "a", at: 1)) == .needsAttention)
        #expect(sessions.apply(event(.notification, message: "b", at: 2)) == nil)
        #expect(sessions.apply(event(.stop, at: 3)) == .finished)
        #expect(sessions.apply(event(.stop, at: 4)) == nil)
    }

    @Test func sessionsAreListedMostRecentFirst() {
        var sessions = AgentSessions()
        sessions.apply(event(.sessionStart, "a", cwd: "/p/a", at: 1))
        sessions.apply(event(.sessionStart, "b", cwd: "/p/b", at: 2))
        sessions.apply(event(.promptSubmit, "a", cwd: "/p/a", at: 3))
        #expect(sessions.list.map(\.id) == ["a", "b"])
    }

    @Test func quietSessionsExpire() {
        var sessions = AgentSessions()
        sessions.apply(event(.sessionStart, "old", at: 0))
        sessions.apply(event(.sessionStart, "new", at: 5000))
        sessions.expire(before: date(1000))
        #expect(sessions.list.map(\.id) == ["new"])
    }

    @Test func aMissingFolderGetsAPlaceholderName() {
        var sessions = AgentSessions()
        sessions.apply(event(.sessionStart, cwd: nil, at: 1))
        #expect(sessions.list[0].project == "?")
        sessions.apply(event(.promptSubmit, cwd: "/Users/me/x", at: 2))
        #expect(sessions.list[0].project == "x")
    }
}

@Suite struct ClaudeHooksInstallerTests {
    private let command = "'/Users/me/Library/Application Support/AraNotch/bin/aranotch-hook' 2>/dev/null || true"

    @Test func addsAHookForEveryEventAndKeepsEverythingElse() throws {
        let settings = try json(#"{"autoMode":true,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        let result = ClaudeHooksInstaller.install(into: settings, command: command)
        #expect(result["autoMode"] as? Bool == true)
        let hooks = try #require(result["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(ClaudeHooksInstaller.events))
        // The user's own Stop hook is still there, next to ours.
        let stop = try #require(hooks["Stop"] as? [[String: Any]])
        let commands = stop.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        #expect(commands == ["say done", command])
        #expect(ClaudeHooksInstaller.isInstalled(in: result))
    }

    @Test func installingTwiceChangesNothingMore() throws {
        let once = ClaudeHooksInstaller.install(into: [:], command: command)
        let twice = ClaudeHooksInstaller.install(into: once, command: command)
        #expect(NSDictionary(dictionary: once) == NSDictionary(dictionary: twice))
    }

    @Test func installingAgainReplacesAnOlderCommandOfOurs() throws {
        let old = ClaudeHooksInstaller.install(into: [:], command: "/old/place/aranotch-hook || true")
        let new = ClaudeHooksInstaller.install(into: old, command: command)
        let data = try JSONSerialization.data(withJSONObject: new)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("old"))
        #expect(text.components(separatedBy: "aranotch-hook").count - 1 == ClaudeHooksInstaller.events.count)
    }

    @Test func uninstallRemovesOnlyOurHooks() throws {
        let settings = try json(#"{"autoMode":true,"hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#)
        let installed = ClaudeHooksInstaller.install(into: settings, command: command)
        let removed = ClaudeHooksInstaller.uninstall(from: installed)
        #expect(NSDictionary(dictionary: removed) == NSDictionary(dictionary: settings))
        #expect(!ClaudeHooksInstaller.isInstalled(in: removed))
    }

    @Test func uninstallLeavesNoEmptyHooksSection() {
        let installed = ClaudeHooksInstaller.install(into: ["model": "x"], command: command)
        let removed = ClaudeHooksInstaller.uninstall(from: installed)
        #expect(NSDictionary(dictionary: removed) == NSDictionary(dictionary: ["model": "x"]))
    }

    @Test func toolEventsMatchEveryTool() throws {
        let hooks = try #require(ClaudeHooksInstaller.install(into: [:], command: command)["hooks"] as? [String: Any])
        let preTool = try #require((hooks["PreToolUse"] as? [[String: Any]])?.first)
        #expect(preTool["matcher"] as? String == "*")
        let stop = try #require((hooks["Stop"] as? [[String: Any]])?.first)
        #expect(stop["matcher"] == nil)
    }

    @Test func theCommandQuotesThePathAndNeverFails() {
        let built = ClaudeHooksInstaller.command(forHelperAt: "/Users/me/Library/Application Support/AraNotch/bin/aranotch-hook")
        #expect(built == command)
    }
}

@Suite struct AgentHostTests {
    @Test func theHostIsTheAppTheAgentsShellRunsIn() {
        let ancestors = [
            "/Users/me/.local/bin/claude", "/bin/zsh", "/usr/bin/login",
            "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", "/sbin/launchd",
        ]
        #expect(AgentHost.appPath(amongAncestors: ancestors) == "/System/Applications/Utilities/Terminal.app")
    }

    @Test func aHelperInsideAnAppCountsAsThatApp() {
        let ancestors = [
            "/bin/zsh",
            "/Applications/Visual Studio Code.app/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)",
            "/Applications/Visual Studio Code.app/Contents/MacOS/Electron",
        ]
        #expect(AgentHost.appPath(amongAncestors: ancestors) == "/Applications/Visual Studio Code.app")
    }

    @Test func theAgentsOwnBundleIsNotItsHost() {
        // Claude Code ships as a bundle of its own; the window it runs in is further up.
        let ancestors = [
            "/Users/me/Library/Application Support/Claude/claude-code/2.1/claude.app/Contents/MacOS/claude",
            "/bin/zsh",
            "/Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper",
            "/Applications/Claude.app/Contents/MacOS/Claude",
            "/sbin/launchd",
        ]
        #expect(AgentHost.appPath(amongAncestors: ancestors) == "/Applications/Claude.app")
    }

    @Test func noAppAmongTheAncestorsMeansNoHost() {
        #expect(AgentHost.appPath(amongAncestors: ["/bin/zsh", "/usr/sbin/sshd", "/sbin/launchd"]) == nil)
        #expect(AgentHost.appPath(amongAncestors: []) == nil)
    }

    @Test func theHostTravelsWithTheEventAndStaysWithTheSession() throws {
        let input = #"{"session_id":"s1","hook_event_name":"SessionStart","cwd":"/Users/me/app"}"#
        let line = try #require(AgentHookInput.compact(Data(input.utf8), at: date(5), hostApp: "/Applications/Ghostty.app"))
        let event = try #require(AgentEventParser.parse(line: line))
        #expect(event.hostApp == "/Applications/Ghostty.app")

        var sessions = AgentSessions()
        sessions.apply(event)
        // A later event without a host does not forget it.
        sessions.apply(AgentEvent(kind: .promptSubmit, sessionID: "s1", cwd: nil, toolName: nil, message: nil, at: date(6)))
        #expect(sessions.session(id: "s1")?.hostApp == "/Applications/Ghostty.app")
    }

    @Test func anEventWithoutAHostHasNone() throws {
        let input = #"{"session_id":"s1","hook_event_name":"Stop"}"#
        let line = try #require(AgentHookInput.compact(Data(input.utf8), at: date(5)))
        #expect(try #require(AgentEventParser.parse(line: line)).hostApp == nil)
    }
}
