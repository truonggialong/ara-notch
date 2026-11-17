import Foundation
import Testing
@testable import AgentCore

@Suite struct AgentAlertsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    private func usage(_ five: Double, resets: Date?, seven: Double? = nil) -> AgentUsage {
        AgentUsage(
            fiveHour: UsageWindow(usedPercent: five, resetsAt: resets),
            sevenDay: seven.map { UsageWindow(usedPercent: $0, resetsAt: nil) }, updatedAt: now)
    }

    @Test func onlyTurnsLongEnoughAreAnnounced() {
        #expect(!FinishNotice.announces(duration: 12, minimum: 60))
        #expect(FinishNotice.announces(duration: 75, minimum: 60))
        #expect(FinishNotice.announces(duration: 3, minimum: 0))
        #expect(FinishNotice.announces(duration: nil, minimum: 300))
    }

    @Test func aWindowIsWarnedAboutOnceWhenItReachesTheThreshold() {
        var alerts = LimitAlerts()
        let resets = now.addingTimeInterval(3600)
        #expect(alerts.update(usage(70, resets: resets), threshold: 80, now: now).isEmpty)
        #expect(alerts.update(usage(82, resets: resets), threshold: 80, now: now) == [.nearing(.fiveHour, percent: 82)])
        #expect(alerts.update(usage(90, resets: resets), threshold: 80, now: now).isEmpty)
    }

    @Test func noWarningsWhenTheyAreOff() {
        var alerts = LimitAlerts()
        #expect(alerts.update(usage(99, resets: nil, seven: 99), threshold: 0, now: now).isEmpty)
        #expect(alerts.update(usage(99, resets: nil), threshold: nil, now: now).isEmpty)
    }

    @Test func aWindowThatStartsAfreshIsSaidOnceAndCanBeWarnedAgain() {
        var alerts = LimitAlerts()
        let first = now.addingTimeInterval(-10)
        _ = alerts.update(usage(85, resets: first), threshold: 80, now: now.addingTimeInterval(-20))
        let next = first.addingTimeInterval(5 * 3600)
        #expect(alerts.update(usage(4, resets: next), threshold: 80, now: now) == [.renewed(.fiveHour)])
        #expect(alerts.update(usage(4, resets: next), threshold: 80, now: now).isEmpty)
        #expect(alerts.update(usage(81, resets: next), threshold: 80, now: now) == [.nearing(.fiveHour, percent: 81)])
    }

    @Test func aResetTimeNotYetPassedIsNotARenewal() {
        var alerts = LimitAlerts()
        _ = alerts.update(usage(10, resets: now.addingTimeInterval(600)), threshold: 80, now: now)
        // Read again with a reset time that moved, before the old one came: not a renewal.
        #expect(alerts.update(usage(12, resets: now.addingTimeInterval(1200)), threshold: 80, now: now).isEmpty)
    }

    @Test func theStopwatchReadsLikeOne() {
        #expect(AgentLiveReadout.stopwatch(42) == "0:42")
        #expect(AgentLiveReadout.stopwatch(12 * 60 + 5) == "12:05")
        #expect(AgentLiveReadout.stopwatch(3725) == "1:02:05")
        #expect(AgentLiveReadout.stopwatch(-3) == "0:00")
    }
}
