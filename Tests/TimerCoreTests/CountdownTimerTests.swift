import Foundation
import Testing
@testable import TimerCore

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct CountdownTimerTests {
    @Test func startsIdle() {
        let timer = CountdownTimer()
        #expect(timer.phase == .idle)
        #expect(timer.remaining(at: at(0)) == 0)
        #expect(timer.progress(at: at(0)) == 0)
    }

    @Test func startRunsForTheDuration() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(100))
        #expect(timer.phase == .running(endsAt: at(160)))
        #expect(timer.duration == 60)
        #expect(timer.remaining(at: at(130)) == 30)
        #expect(timer.progress(at: at(130)) == 0.5)
    }

    @Test func tickFinishesExactlyOnce() {
        var timer = CountdownTimer()
        timer.start(duration: 10, at: at(0))
        let early = timer.tick(at: at(9.9))
        #expect(!early)
        let onTime = timer.tick(at: at(10))
        #expect(onTime)
        #expect(timer.phase == .finished)
        let again = timer.tick(at: at(11))
        #expect(!again)
    }

    @Test func lateTickStillFinishesOnce() {
        var timer = CountdownTimer()
        timer.start(duration: 10, at: at(0))
        let late = timer.tick(at: at(500))
        let later = timer.tick(at: at(501))
        #expect(late)
        #expect(!later)
        #expect(timer.remaining(at: at(500)) == 0)
        #expect(timer.progress(at: at(500)) == 1)
    }

    @Test func remainingIsNeverNegative() {
        var timer = CountdownTimer()
        timer.start(duration: 10, at: at(0))
        #expect(timer.remaining(at: at(50)) == 0)
        #expect(timer.progress(at: at(50)) == 1)
    }

    @Test func pauseKeepsTheRemainingTime() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.pause(at: at(20))
        #expect(timer.phase == .paused(remaining: 40))
        #expect(timer.remaining(at: at(999)) == 40)
        let finished = timer.tick(at: at(999))
        #expect(!finished)
    }

    @Test func resumeContinuesFromWhereItStopped() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.pause(at: at(20))
        timer.resume(at: at(100))
        #expect(timer.phase == .running(endsAt: at(140)))
    }

    @Test func repeatedPauseAndResumeKeepTheTotal() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.pause(at: at(10))
        timer.resume(at: at(50))
        timer.pause(at: at(70))
        timer.resume(at: at(200))
        // 10 s + 20 s have run; 30 s remain.
        #expect(timer.remaining(at: at(200)) == 30)
        #expect(timer.progress(at: at(200)) == 0.5)
    }

    @Test func cancelReturnsToIdle() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.cancel()
        #expect(timer.phase == .idle)
        #expect(timer.remaining(at: at(1)) == 0)
    }

    @Test func actionsInTheWrongStateDoNothing() {
        var idle = CountdownTimer()
        idle.pause(at: at(0))
        idle.resume(at: at(0))
        idle.cancel()
        #expect(idle.phase == .idle)

        var running = CountdownTimer()
        running.start(duration: 60, at: at(0))
        running.resume(at: at(10))
        #expect(running.phase == .running(endsAt: at(60)))

        var paused = running
        paused.pause(at: at(10))
        paused.pause(at: at(30))
        #expect(paused.phase == .paused(remaining: 50))
    }

    @Test func startingAgainReplacesTheCountdown() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.start(duration: 5, at: at(10))
        #expect(timer.phase == .running(endsAt: at(15)))
        #expect(timer.duration == 5)
    }

    @Test func startAfterFinishing() {
        var timer = CountdownTimer()
        timer.start(duration: 1, at: at(0))
        _ = timer.tick(at: at(1))
        timer.start(duration: 2, at: at(5))
        #expect(timer.phase == .running(endsAt: at(7)))
    }

    @Test(arguments: [(0.0, 1.0), (-5.0, 1.0), (0.5, 1.0), (10_800.0, 10_800.0), (99_999.0, 10_800.0), (Double.nan, 1.0)])
    func durationIsClamped(input: Double, expected: Double) {
        var timer = CountdownTimer()
        timer.start(duration: input, at: at(0))
        #expect(timer.duration == expected)
    }
}

@Suite struct TimerFormatTests {
    @Test(arguments: [
        (0.0, "0:00"), (0.4, "0:01"), (59.0, "0:59"), (59.2, "1:00"), (60.0, "1:00"), (1499.0, "24:59"),
        (1500.0, "25:00"), (3599.5, "1:00:00"), (3900.0, "1:05:00"), (10_800.0, "3:00:00"), (-3.0, "0:00"),
    ])
    func clock(seconds: Double, expected: String) {
        #expect(TimerFormat.clock(seconds) == expected)
    }
}

@Suite struct TimerSettingsStoreTests {
    @Test func defaults() {
        let store = TimerSettingsStore(defaults: InMemoryDefaults())
        #expect(store.minutes == 25)
        #expect(store.soundEnabled == true)
    }

    @Test func valuesRoundTripAndClamp() {
        let defaults = InMemoryDefaults()
        let store = TimerSettingsStore(defaults: defaults)
        store.minutes = 40
        store.soundEnabled = false
        let reopened = TimerSettingsStore(defaults: defaults)
        #expect(reopened.minutes == 40)
        #expect(reopened.soundEnabled == false)
        store.minutes = 0
        #expect(store.minutes == 1)
        store.minutes = 999
        #expect(store.minutes == 180)
    }

    @Test func wrongTypesFallBackToDefaults() {
        let defaults = InMemoryDefaults()
        defaults.set("abc", forKey: "timer.minutes")
        defaults.set("abc", forKey: "timer.sound")
        let store = TimerSettingsStore(defaults: defaults)
        #expect(store.minutes == 25)
        #expect(store.soundEnabled == true)
    }
}
