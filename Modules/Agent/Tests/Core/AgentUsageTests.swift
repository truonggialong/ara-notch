import Foundation
import Testing
@testable import AgentCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let statusInput = Data("""
{"session_id":"abc","model":{"display_name":"Opus"},"cwd":"/Users/a/proj",
 "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},
                "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
""".utf8)

@Suite struct ClaudeStatusInputTests {
    @Test func readsBothRateLimitWindows() throws {
        let usage = try #require(ClaudeStatusInput.usage(from: statusInput, at: date(100)))
        #expect(usage.fiveHour == UsageWindow(usedPercent: 23.5, resetsAt: date(1_738_425_600)))
        #expect(usage.sevenDay == UsageWindow(usedPercent: 41.2, resetsAt: date(1_738_857_600)))
        #expect(usage.updatedAt == date(100))
    }

    @Test func aWindowMayBeMissing() throws {
        let input = Data(#"{"rate_limits":{"seven_day":{"used_percentage":9,"resets_at":500}}}"#.utf8)
        let usage = try #require(ClaudeStatusInput.usage(from: input, at: date(1)))
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay?.usedPercent == 9)
    }

    @Test func noRateLimitsIsNoUsage() {
        // API-key users and the first moments of a session have no rate limit data.
        #expect(ClaudeStatusInput.usage(from: Data(#"{"session_id":"abc"}"#.utf8), at: date(1)) == nil)
        #expect(ClaudeStatusInput.usage(from: Data(#"{"rate_limits":{}}"#.utf8), at: date(1)) == nil)
        #expect(ClaudeStatusInput.usage(from: Data("not json".utf8), at: date(1)) == nil)
    }

    @Test func theModelNameIsRead() {
        #expect(ClaudeStatusInput.modelName(from: statusInput) == "Opus")
        #expect(ClaudeStatusInput.modelName(from: Data("{}".utf8)) == nil)
    }
}

@Suite struct AgentUsageRecordTests {
    @Test func aRecordSurvivesBeingWrittenAndRead() throws {
        let usage = try #require(ClaudeStatusInput.usage(from: statusInput, at: date(100)))
        let line = try #require(usage.record)
        #expect(!line.contains("\n"))
        #expect(AgentUsage(record: line) == usage)
    }

    @Test func aRecordHoldsNothingButNumbers() throws {
        // The status line input also carries the folder and the session; none of it is kept.
        let usage = try #require(ClaudeStatusInput.usage(from: statusInput, at: date(100)))
        let line = try #require(usage.record)
        #expect(!line.contains("proj"))
        #expect(!line.contains("abc"))
    }

    @Test func rubbishIsNoRecord() {
        #expect(AgentUsage(record: "") == nil)
        #expect(AgentUsage(record: "{}") == nil)
    }
}

@Suite struct UsageWindowTests {
    @Test func aWindowPastItsResetIsNotKnown() {
        // What was used since the reset was never reported: not 0%, but no number at all.
        let window = UsageWindow(usedPercent: 80, resetsAt: date(1000))
        #expect(window.current(at: date(999))?.usedPercent == 80)
        #expect(window.current(at: date(1000)) == nil)
    }

    @Test func aWindowWithNoResetTimeIsKept() {
        #expect(UsageWindow(usedPercent: 12, resetsAt: nil).current(at: date(9_999_999))?.usedPercent == 12)
    }

    @Test func aReportOlderThanAWeekIsOld() {
        let usage = AgentUsage(fiveHour: UsageWindow(usedPercent: 65, resetsAt: nil), sevenDay: nil, updatedAt: date(0))
        #expect(!usage.isOld(at: date(7 * 86_400)))
        #expect(usage.isOld(at: date(7 * 86_400 + 1)))
    }

    @Test func theNewerReportStands() {
        let old = AgentUsage(fiveHour: UsageWindow(usedPercent: 14, resetsAt: nil), sevenDay: nil, updatedAt: date(100))
        let new = AgentUsage(fiveHour: UsageWindow(usedPercent: 29, resetsAt: nil), sevenDay: nil, updatedAt: date(200))
        #expect(AgentUsage.latest(old, new) == new)
        #expect(AgentUsage.latest(new, old) == new)
        #expect(AgentUsage.latest(nil, old) == old)
        #expect(AgentUsage.latest(old, nil) == old)
        #expect(AgentUsage.latest(nil, nil) == nil)
    }
}

@Suite struct ClaudeStatusLineTextTests {
    @Test func showsBothWindowsRounded() throws {
        let usage = try #require(ClaudeStatusInput.usage(from: statusInput, at: date(100)))
        #expect(ClaudeStatusLine.text(usage: usage, modelName: "Opus") == "Opus · 5h 24% · 7d 41%")
    }

    @Test func withoutLimitsOnlyTheModelIsShown() {
        #expect(ClaudeStatusLine.text(usage: nil, modelName: "Opus") == "Opus")
        #expect(ClaudeStatusLine.text(usage: nil, modelName: nil) == "")
    }
}

@Suite struct ClaudeStatusLineInstallerTests {
    private let command = "'/tmp/aranotch-hook' --statusline 2>/dev/null || true"

    @Test func installsWhenThereIsNoStatusLine() throws {
        let settings = try #require(ClaudeStatusLineInstaller.install(into: ["hooks": ["x": 1]], command: command))
        let line = try #require(settings["statusLine"] as? [String: Any])
        #expect(line["type"] as? String == "command")
        #expect(line["command"] as? String == command)
        #expect(settings["hooks"] != nil)
        #expect(ClaudeStatusLineInstaller.state(of: settings) == .installed)
    }

    @Test func aStatusLineOfTheUsersOwnIsLeftAlone() {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": "~/.claude/my-line.sh"]]
        #expect(ClaudeStatusLineInstaller.state(of: settings) == .foreign)
        #expect(ClaudeStatusLineInstaller.install(into: settings, command: command) == nil)
        #expect(ClaudeStatusLineInstaller.uninstall(from: settings)["statusLine"] != nil)
    }

    @Test func removingTakesOutOnlyOurStatusLine() throws {
        let installed = try #require(ClaudeStatusLineInstaller.install(into: ["model": "x"], command: command))
        let removed = ClaudeStatusLineInstaller.uninstall(from: installed)
        #expect(removed["statusLine"] == nil)
        #expect(removed["model"] as? String == "x")
        #expect(ClaudeStatusLineInstaller.state(of: removed) == .absent)
    }

    @Test func installingTwiceIsInstallingOnce() throws {
        let once = try #require(ClaudeStatusLineInstaller.install(into: [:], command: command))
        let twice = try #require(ClaudeStatusLineInstaller.install(into: once, command: command))
        #expect((twice["statusLine"] as? [String: Any])?["command"] as? String == command)
    }
}

@Suite struct CodexRolloutParserTests {
    @Test func readsTheSessionAndItsFolder() {
        let line = #"{"timestamp":"2026-10-07T01:15:31.250Z","type":"session_meta","payload":{"id":"01a1-x","session_id":"01a1-x","cwd":"/Users/a/Documents/app"}}"#
        guard case .session(let id, let cwd, let at) = CodexRolloutParser.parse(line: line) else {
            Issue.record("not a session line")
            return
        }
        #expect(id == "01a1-x")
        #expect(cwd == "/Users/a/Documents/app")
        #expect(abs(at.timeIntervalSince1970 - 1_791_335_731.25) < 0.01)
    }

    @Test func readsTurnsStartingAndEnding() {
        let started = #"{"timestamp":"2026-10-07T01:16:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"t1"}}"#
        let completed = #"{"timestamp":"2026-10-07T01:20:00.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"t1","last_agent_message":"secret text"}}"#
        let aborted = #"{"timestamp":"2026-10-07T01:21:00.000Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#
        if case .taskStarted = CodexRolloutParser.parse(line: started) {} else { Issue.record("task_started not read") }
        if case .taskEnded = CodexRolloutParser.parse(line: completed) {} else { Issue.record("task_complete not read") }
        if case .taskEnded = CodexRolloutParser.parse(line: aborted) {} else { Issue.record("turn_aborted not read") }
    }

    @Test func readsTheRateLimits() {
        let line = #"{"timestamp":"2026-10-07T01:17:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":30943}},"rate_limits":{"primary":{"used_percent":50.0,"window_minutes":300,"resets_at":1791312210},"secondary":{"used_percent":55.0,"window_minutes":10080,"resets_at":1791791700},"plan_type":"plus"}}}"#
        guard case .usage(let usage) = CodexRolloutParser.parse(line: line) else {
            Issue.record("no usage")
            return
        }
        #expect(usage.fiveHour == UsageWindow(usedPercent: 50, resetsAt: date(1_791_312_210)))
        #expect(usage.sevenDay == UsageWindow(usedPercent: 55, resetsAt: date(1_791_791_700)))
    }

    @Test func aTokenCountWithoutLimitsIsSkipped() {
        let line = #"{"timestamp":"2026-10-07T01:17:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{}}}"#
        #expect(CodexRolloutParser.parse(line: line) == nil)
    }

    @Test func everythingElseIsSkipped() {
        // Messages, tool calls and their output are never looked at.
        #expect(CodexRolloutParser.parse(line: #"{"timestamp":"2026-10-07T01:17:00.000Z","type":"response_item","payload":{"type":"message","content":"hello"}}"#) == nil)
        #expect(CodexRolloutParser.parse(line: "") == nil)
        #expect(CodexRolloutParser.parse(line: "{broken") == nil)
    }

    @Test func aCheapCheckTellsWhetherALineIsWorthParsing() {
        #expect(CodexRolloutParser.mayMatter(#"{"type":"event_msg","payload":{"type":"task_started"}}"#))
        #expect(!CodexRolloutParser.mayMatter(#"{"type":"response_item","payload":{"type":"function_call"}}"#))
    }
}

@Suite struct CodexSessionEventsTests {
    @Test func aCodexSessionShowsUpLikeAnyOther() {
        var sessions = AgentSessions()
        let id = "01a1-x"
        for event in [
            CodexRolloutEvent.session(id: id, cwd: "/Users/a/Documents/app", at: date(10)),
            .taskStarted(at: date(20)),
        ] {
            CodexRolloutEvent.agentEvent(for: event, sessionID: id).map { _ = sessions.apply($0) }
        }
        let session = sessions.list.first
        #expect(session?.id == "codex:01a1-x")
        #expect(session?.project == "app")
        #expect(session?.state == .working(tool: nil))
        #expect(session?.isCodex == true)
    }

    @Test func aFinishedTurnIsAnnounced() {
        var sessions = AgentSessions()
        _ = CodexRolloutEvent.agentEvent(for: .taskStarted(at: date(20)), sessionID: "s").map { sessions.apply($0) }
        let announcement = CodexRolloutEvent.agentEvent(for: .taskEnded(at: date(30)), sessionID: "s")
            .flatMap { sessions.apply($0) }
        #expect(announcement == .finished)
    }

    @Test func usageLinesAreNotSessionEvents() {
        let usage = AgentUsage(fiveHour: nil, sevenDay: UsageWindow(usedPercent: 1, resetsAt: nil), updatedAt: date(1))
        #expect(CodexRolloutEvent.agentEvent(for: .usage(usage), sessionID: "s") == nil)
    }
}

@Suite struct AgentUsageSettingsTests {
    @Test func codexIsNotFollowedUntilTurnedOn() {
        let defaults = InMemoryDefaults()
        let store = AgentSettingsStore(defaults: defaults)
        #expect(store.tracksCodex == false)
        store.tracksCodex = true
        #expect(AgentSettingsStore(defaults: defaults).tracksCodex == true)
    }
}

@Suite struct ClaudeAccountUsageTests {
    private let response = Data("""
    {"five_hour": {"utilization": 29.0, "resets_at": "2026-10-18T19:30:00.661633+00:00"},
     "seven_day": {"utilization": 41, "resets_at": "2026-10-23T06:00:00Z"},
     "seven_day_oauth_apps": null, "seven_day_opus": null,
     "extra_usage": {"is_enabled": false}}
    """.utf8)

    @Test func readsBothWindowsAndTheirResets() throws {
        let usage = try #require(ClaudeAccountUsage.usage(from: response, at: date(500)))
        #expect(usage.fiveHour?.usedPercent == 29)
        #expect(abs((usage.fiveHour?.resetsAt?.timeIntervalSince1970 ?? 0) - 1_792_351_800.661633) < 0.001)
        #expect(usage.sevenDay?.usedPercent == 41)
        #expect(usage.sevenDay?.resetsAt == Date(timeIntervalSince1970: 1_792_735_200))
        #expect(usage.updatedAt == date(500))
    }

    @Test func aWindowWithoutANumberIsLeftOut() throws {
        let partial = Data(#"{"five_hour": null, "seven_day": {"utilization": 3, "resets_at": null}}"#.utf8)
        let usage = try #require(ClaudeAccountUsage.usage(from: partial, at: date(1)))
        #expect(usage.fiveHour == nil)
        #expect(usage.sevenDay == UsageWindow(usedPercent: 3, resetsAt: nil))
    }

    @Test func noWindowsIsNoUsage() {
        #expect(ClaudeAccountUsage.usage(from: Data(#"{"limits": []}"#.utf8), at: date(1)) == nil)
        #expect(ClaudeAccountUsage.usage(from: Data("not json".utf8), at: date(1)) == nil)
    }
}

@Suite struct ClaudeLoginTests {
    private func login(expiresAt milliseconds: Double?) -> Data {
        var oauth: [String: Any] = ["accessToken": "test-access", "refreshToken": "test-refresh"]
        if let milliseconds { oauth["expiresAt"] = milliseconds }
        return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
    }

    @Test func aLoginStillValidGivesItsAccessToken() {
        #expect(ClaudeLogin.read(login(expiresAt: 2_000_000), now: date(1_000)) == .valid(accessToken: "test-access"))
    }

    @Test func aLoginPastItsExpiryIsExpired() {
        #expect(ClaudeLogin.read(login(expiresAt: 2_000_000), now: date(2_000)) == .expired)
    }

    @Test func aLoginWithoutAnExpiryIsTakenAsValid() {
        #expect(ClaudeLogin.read(login(expiresAt: nil), now: date(1)) == .valid(accessToken: "test-access"))
    }

    @Test func somethingElseIsNoLogin() {
        #expect(ClaudeLogin.read(Data("{}".utf8), now: date(1)) == nil)
        #expect(ClaudeLogin.read(Data("garbage".utf8), now: date(1)) == nil)
        #expect(ClaudeLogin.read(try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": ""]]), now: date(1)) == nil)
    }
}

@Suite struct ClaudeAccountSettingTests {
    @Test func readingTheAccountIsOffUntilTheUserTurnsItOn() {
        let defaults = UserDefaults(suiteName: "aranotch.test.account.\(UUID().uuidString)")!
        let store = AgentSettingsStore(defaults: defaults)
        #expect(!store.readsClaudeAccount)
        store.readsClaudeAccount = true
        #expect(AgentSettingsStore(defaults: defaults).readsClaudeAccount)
    }
}
