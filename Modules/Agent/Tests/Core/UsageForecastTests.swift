import Foundation
import Testing
@testable import AgentCore

@Suite struct UsageForecastTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    private func usage(used: Double, at offset: TimeInterval = -30, resetsIn: TimeInterval = 3_600) -> AgentUsage {
        AgentUsage(
            fiveHour: UsageWindow(usedPercent: used, resetsAt: now.addingTimeInterval(resetsIn)), sevenDay: nil,
            updatedAt: now.addingTimeInterval(offset))
    }

    private func event(_ kind: AgentEvent.Kind, _ session: String = "s1", at offset: TimeInterval = 0) -> AgentEvent {
        AgentEvent(kind: kind, sessionID: session, cwd: "/tmp/demo", toolName: nil, message: nil, at: now.addingTimeInterval(offset))
    }

    // MARK: - A turn that begins

    @Test func aTurnThatBeginsIsAnnouncedOnce() {
        var sessions = AgentSessions()
        #expect(sessions.apply(event(.sessionStart)) == nil)
        #expect(sessions.apply(event(.promptSubmit)) == .started)
        // Its tools, and a second request sent while it works, announce nothing more.
        #expect(sessions.apply(event(.toolUse)) == nil)
        #expect(sessions.apply(event(.promptSubmit)) == nil)
        #expect(sessions.apply(event(.stop)) == .finished)
        // The next turn is announced again.
        #expect(sessions.apply(event(.promptSubmit)) == .started)
    }

    // MARK: - What is left and what a turn takes

    @Test func whatIsLeftIsWhatTheAgentReportedLast() {
        let forecast = UsageForecast(usage: usage(used: 14), costs: [], now: now)!
        #expect(forecast.remainingPercent == 86)
        // Too few turns measured to say what this one takes.
        #expect(forecast.estimatedCostPercent == nil)
        #expect(forecast.expectedRemainingPercent == nil)
        #expect(!forecast.isStale(at: now))
    }

    @Test func aTurnIsExpectedToTakeWhatRecentTurnsTook() {
        // The middle one of the last ten: one costly turn does not carry the estimate away.
        let forecast = UsageForecast(usage: usage(used: 14), costs: [2, 3, 30, 4], now: now)!
        #expect(forecast.estimatedCostPercent == 3.5)
        #expect(forecast.expectedRemainingPercent == 82.5)
        #expect(UsageForecast.estimate(from: [1, 2]) == nil)
        #expect(UsageForecast.estimate(from: [1, 2, 3]) == 2)
        #expect(UsageForecast.estimate(from: Array(repeating: 9, count: 5) + Array(repeating: 1, count: 10)) == 1)
    }

    @Test func nothingIsLeftBelowNothing() {
        let forecast = UsageForecast(usage: usage(used: 99), costs: [4, 4, 4], now: now)!
        #expect(forecast.remainingPercent == 1)
        #expect(forecast.expectedRemainingPercent == 0)
        #expect(UsageForecast(usage: usage(used: 130), costs: [], now: now)!.remainingPercent == 0)
    }

    @Test func aNumberFromAWindowThatHasEndedSaysNothingOfThePresentOne() {
        // The window started afresh since the agent last reported: what has been used of
        // the new one is not known, and is not made up.
        #expect(UsageForecast(usage: usage(used: 80, at: -7_200, resetsIn: -60), costs: [1, 2, 3], now: now) == nil)
    }

    @Test func anOldNumberSaysItIsOld() {
        // An agent in the desktop app reports nothing; the last number may be hours old.
        let forecast = UsageForecast(usage: usage(used: 14, at: -7 * 3_600, resetsIn: 600), costs: [], now: now)!
        #expect(forecast.isStale(at: now))
        #expect(forecast.asOf == now.addingTimeInterval(-7 * 3_600))
        #expect(UsageForecast(usage: nil, costs: [1, 2, 3], now: now) == nil)
    }

    // MARK: - What turns took

    @Test func aTurnCostsWhatTheWindowRoseByWhileItRan() {
        var ledger = TurnCostLedger()
        ledger.begin(sessionID: "s1", usage: usage(used: 14, at: -100), at: now.addingTimeInterval(-90))
        // Reported again while the turn ran.
        let cost = ledger.end(sessionID: "s1", usage: usage(used: 17, at: -5), at: now)
        #expect(cost == 3)
        #expect(ledger.costs == [3])
    }

    @Test func aTurnIsNotMeasuredWithoutNumbersFromBothEnds() {
        var ledger = TurnCostLedger()
        // The number at the start is hours old: the agent is not reporting.
        ledger.begin(sessionID: "old", usage: usage(used: 14, at: -7_200), at: now.addingTimeInterval(-60))
        #expect(ledger.end(sessionID: "old", usage: usage(used: 20, at: -5), at: now) == nil)
        // Nothing was reported since the turn began.
        ledger.begin(sessionID: "silent", usage: usage(used: 14, at: -100), at: now.addingTimeInterval(-90))
        #expect(ledger.end(sessionID: "silent", usage: usage(used: 14, at: -100), at: now) == nil)
        // The window started afresh in between.
        ledger.begin(sessionID: "reset", usage: usage(used: 90, at: -100, resetsIn: -50), at: now.addingTimeInterval(-90))
        #expect(ledger.end(sessionID: "reset", usage: usage(used: 2, at: -5), at: now) == nil)
        // A turn that was never seen to begin.
        #expect(ledger.end(sessionID: "unknown", usage: usage(used: 2, at: -5), at: now) == nil)
        #expect(ledger.costs.isEmpty)
    }

    @Test func turnsThatRanTogetherAreNotMeasured() {
        // Two agents draw on the same window; what it rose by is not one turn's doing.
        var ledger = TurnCostLedger()
        ledger.begin(sessionID: "a", usage: usage(used: 10, at: -100), at: now.addingTimeInterval(-90))
        ledger.begin(sessionID: "b", usage: usage(used: 11, at: -80), at: now.addingTimeInterval(-70))
        #expect(ledger.end(sessionID: "a", usage: usage(used: 15, at: -5), at: now) == nil)
        #expect(ledger.end(sessionID: "b", usage: usage(used: 16, at: -1), at: now) == nil)
    }

    @Test func onlyTheLatestTurnsAreKept() {
        var ledger = TurnCostLedger(costs: Array(repeating: 1, count: TurnCostLedger.capacity))
        ledger.begin(sessionID: "s", usage: usage(used: 10, at: -100), at: now.addingTimeInterval(-90))
        ledger.end(sessionID: "s", usage: usage(used: 15, at: -5), at: now)
        #expect(ledger.costs.count == TurnCostLedger.capacity)
        #expect(ledger.costs.last == 5)
    }

    @Test func whatTurnsTookAndTheStartSwitchAreRemembered() {
        let defaults = InMemoryDefaults()
        let store = AgentSettingsStore(defaults: defaults)
        #expect(store.announcesWorking)
        #expect(store.turnCosts(codex: false).isEmpty)
        store.announcesWorking = false
        store.setTurnCosts([2, 3.5], codex: false)
        store.setTurnCosts([7], codex: true)
        let again = AgentSettingsStore(defaults: defaults)
        #expect(!again.announcesWorking)
        #expect(again.turnCosts(codex: false) == [2, 3.5])
        #expect(again.turnCosts(codex: true) == [7])
    }
}

@Suite struct AgentNoticeTextTests {
    @Test func whatAnAgentSaidFitsTwoLinesOfASignBrokenBetweenWords() {
        #expect(AgentNoticeText.lines(of: "") == [])
        #expect(AgentNoticeText.lines(of: "Cần quyền chạy Bash") == ["Cần quyền chạy Bash"])
        #expect(AgentNoticeText.lines(of: "Claude needs your permission to use Bash", width: 30)
            == ["Claude needs your permission", "to use Bash"])
        // What does not fit two lines is cut, and says so.
        #expect(AgentNoticeText.lines(of: "one two three four five six seven eight nine ten", width: 12)
            == ["one two", "three four…"])
    }
}
