import Foundation
import Testing
@testable import AgentCore

@Suite struct AgentPacingTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func theProcessListIsReadOnlyWithClaudeSessionsAndNotTooOften() {
        #expect(!AgentPacing.readsProcessList(claudeSessions: 0, lastRead: nil, now: now))
        #expect(AgentPacing.readsProcessList(claudeSessions: 1, lastRead: nil, now: now))
        #expect(!AgentPacing.readsProcessList(claudeSessions: 2, lastRead: now.addingTimeInterval(-60), now: now))
        #expect(AgentPacing.readsProcessList(claudeSessions: 2, lastRead: now.addingTimeInterval(-120), now: now))
    }

    @Test func onlyLogsWrittenInTheLastHalfHourAreReadAgain() {
        let writes = [
            "a": now.addingTimeInterval(-10), "b": now.addingTimeInterval(-29 * 60), "c": now.addingTimeInterval(-31 * 60),
        ]
        #expect(AgentPacing.openLogs(writes, now: now) == ["a", "b"])
        #expect(AgentPacing.openLogs([:], now: now).isEmpty)
    }

    @Test func theAccountIsAskedOftenerWhileItsPageShows() {
        #expect(AgentPacing.accountDelay(pageShown: true, failures: 0) == 60)
        #expect(AgentPacing.accountDelay(pageShown: false, failures: 0) == 300)
    }

    @Test func failedChecksWaitLongerEachTimeUpToHalfAnHour() {
        #expect(AgentPacing.accountDelay(pageShown: false, failures: 1) == 300)
        #expect(AgentPacing.accountDelay(pageShown: false, failures: 2) == 600)
        #expect(AgentPacing.accountDelay(pageShown: true, failures: 3) == 1200)
        #expect(AgentPacing.accountDelay(pageShown: false, failures: 12) == 1800)
    }

    @Test func aReadingAMinuteOldIsAskedAgainWhenThePageShows() {
        #expect(AgentPacing.accountIsStale(lastRead: nil, now: now))
        #expect(!AgentPacing.accountIsStale(lastRead: now.addingTimeInterval(-30), now: now))
        #expect(AgentPacing.accountIsStale(lastRead: now.addingTimeInterval(-61), now: now))
    }
}
