import Foundation
import Testing
@testable import AgentCore

@Suite struct ClaudeUsageSourcesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func line(_ text: String) -> Data { Data(text.utf8) }

    @Test func claudeCodeLimitsAreRead() throws {
        let reply = ClaudeCodeUsage.reply(fromLine: line(#"{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"subscription_type":"pro","rate_limits":{"five_hour":{"utilization":42,"resets_at":"2027-01-15T08:00:00Z"},"seven_day":{"utilization":13.5,"resets_at":null}}}}}"#), at: now)
        guard case .usage(let usage) = reply else { Issue.record("no usage: \(String(describing: reply))"); return }
        #expect(usage.fiveHour?.usedPercent == 42)
        #expect(usage.fiveHour?.resetsAt != nil)
        #expect(usage.sevenDay?.usedPercent == 13.5)
        #expect(usage.updatedAt == now)
    }

    @Test func noNumbersIsEmptyNotAnError() {
        // What Claude Code 2.1.323 answered on the owner's Pro account.
        let reply = ClaudeCodeUsage.reply(fromLine: line(#"{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":false,"rate_limits":null,"subscription_type":"pro"}}}"#), at: now)
        #expect(reply == .empty)
        let failed = ClaudeCodeUsage.reply(fromLine: line(#"{"type":"control_response","response":{"subtype":"error","request_id":"usage","error":"unknown subtype"}}"#), at: now)
        #expect(failed == .empty)
    }

    @Test func otherLinesAreNotTheReply() {
        #expect(ClaudeCodeUsage.reply(fromLine: line(#"{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{}}}"#), at: now) == nil)
        #expect(ClaudeCodeUsage.reply(fromLine: line(#"{"type":"system","subtype":"init"}"#), at: now) == nil)
        #expect(ClaudeCodeUsage.reply(fromLine: line("not json"), at: now) == nil)
    }

    @Test func claudeCodeRunsWithoutTheUsersAccountOverrides() {
        let environment = ClaudeCodeUsage.environment([
            "PATH": "/usr/bin", "CLAUDECODE": "1", "CLAUDE_CONFIG_DIR": "/x", "ANTHROPIC_API_KEY": "k", "HOME": "/Users/a",
        ])
        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment["HOME"] == "/Users/a")
        #expect(environment["CLAUDECODE"] == nil)
        #expect(environment["CLAUDE_CONFIG_DIR"] == nil)
        #expect(environment["ANTHROPIC_API_KEY"] == nil)
        #expect(environment["DISABLE_AUTOUPDATER"] == "1")
    }

    private func history(version: Int, _ samples: [String]) -> Data {
        Data(#"{"version":\#(version),"samples":[\#(samples.joined(separator: ","))]}"#.utf8)
    }

    private func ms(_ secondsAgo: TimeInterval) -> Int { Int((now.timeIntervalSince1970 - secondsAgo) * 1000) }

    @Test func theAppsNewestFreshReadingIsUsed() {
        let data = history(version: 2, [
            #"{"t":\#(ms(1200)),"org":"o","u":{"fh":10,"sd":5}}"#,
            #"{"t":\#(ms(120)),"org":"o","u":{"fh":31,"sd":7,"so":2}}"#,
        ])
        let usage = ClaudeAppUsage.usage(from: data, now: now)
        #expect(usage?.fiveHour == UsageWindow(usedPercent: 31, resetsAt: nil))
        #expect(usage?.sevenDay == UsageWindow(usedPercent: 7, resetsAt: nil))
    }

    @Test func theFirstVersionKeepsNumbersBesideTheTime() {
        let usage = ClaudeAppUsage.usage(from: history(version: 1, [#"{"t":\#(ms(60)),"fh":120,"sd":-4}"#]), now: now)
        #expect(usage?.fiveHour?.usedPercent == 100)
        #expect(usage?.sevenDay?.usedPercent == 0)
    }

    @Test func aStaleOrUnknownFileGivesNothing() {
        // The owner's file was last written six weeks before the test: the app had stopped checking.
        #expect(ClaudeAppUsage.usage(from: history(version: 2, [#"{"t":\#(ms(31 * 60)),"u":{"fh":10}}"#]), now: now) == nil)
        #expect(ClaudeAppUsage.usage(from: history(version: 3, [#"{"t":\#(ms(60)),"u":{"fh":10}}"#]), now: now) == nil)
        #expect(ClaudeAppUsage.usage(from: history(version: 2, [#"{"t":\#(ms(60)),"u":{"fh":true}}"#]), now: now) == nil)
        #expect(ClaudeAppUsage.usage(from: Data("{}".utf8), now: now) == nil)
    }

    @Test func claudeCodeIsAskedLessAndLessWhileItHasNoNumbers() {
        #expect(AgentPacing.claudeCodeWait(empties: 0) == 0)
        #expect(AgentPacing.claudeCodeWait(empties: 1) == 600)
        #expect(AgentPacing.claudeCodeWait(empties: 2) == 1200)
        #expect(AgentPacing.claudeCodeWait(empties: 20) == 6 * 3600)
    }
}
