import Foundation
import Testing
@testable import TimerCore

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct CountdownExtensionTests {
    @Test func timeAddedToARunningCountdownMovesItsEnd() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.extend(by: 300, at: at(10))
        #expect(timer.remaining(at: at(10)) == 350)
        #expect(timer.duration == 360)
    }

    @Test func timeAddedToAPausedCountdownWaitsWithIt() {
        var timer = CountdownTimer()
        timer.start(duration: 60, at: at(0))
        timer.pause(at: at(20))
        timer.extend(by: 60, at: at(500))
        #expect(timer.phase == .paused(remaining: 100))
        #expect(timer.duration == 120)
    }

    @Test func aCountdownIsNeverExtendedPastTheLongestOne() {
        var timer = CountdownTimer()
        timer.start(duration: 10_700, at: at(0))
        timer.extend(by: 300, at: at(0))
        #expect(timer.remaining(at: at(0)) == 10_800)
        #expect(timer.duration == 10_800)
    }

    @Test func nothingIsAddedToACountdownThatIsNotUnderWay() {
        var idle = CountdownTimer()
        idle.extend(by: 60, at: at(0))
        #expect(idle.phase == .idle)
        var done = CountdownTimer()
        done.start(duration: 1, at: at(0))
        _ = done.tick(at: at(2))
        done.extend(by: 60, at: at(3))
        #expect(done.phase == .finished)
    }
}

@Suite struct TimerBoardTests {
    @Test func countdownsAreKeptInTheOrderTheyWereStarted() {
        var board = TimerBoard()
        let tea = board.add(duration: 180, label: "Tea", at: at(0))
        let call = board.add(duration: 600, label: "", at: at(5))
        #expect(tea != nil && call != nil && tea != call)
        #expect(board.entries.map(\.label) == ["Tea", ""])
    }

    @Test func thereIsRoomForFourAtOnce() {
        var board = TimerBoard()
        for _ in 0..<TimerBoard.capacity {
            #expect(board.add(duration: 60, label: "", at: at(0)) != nil)
        }
        #expect(board.isFull)
        #expect(board.add(duration: 60, label: "", at: at(0)) == nil)
        #expect(TimerBoard.capacity == 4)
    }

    @Test func eachCountdownIsReportedOnceWhenItEnds() {
        var board = TimerBoard()
        _ = board.add(duration: 10, label: "short", at: at(0))
        _ = board.add(duration: 100, label: "long", at: at(0))
        let early = board.tick(at: at(5))
        #expect(early.isEmpty)
        let ended = board.tick(at: at(10))
        #expect(ended.map(\.label) == ["short"])
        let again = board.tick(at: at(11))
        #expect(again.isEmpty)
    }

    @Test func theOneEndingSoonestIsTheOneShownBesideTheNotch() {
        var board = TimerBoard()
        let long = board.add(duration: 600, label: "long", at: at(0))!
        let short = board.add(duration: 120, label: "short", at: at(0))!
        #expect(board.soonest(at: at(1))?.id == short)
        // A paused one is not about to end.
        board.pause(short, at: at(2))
        #expect(board.soonest(at: at(3))?.id == long)
        board.pause(long, at: at(4))
        #expect(board.soonest(at: at(5)) == nil)
        #expect(!board.hasRunning)
    }

    @Test func oneCountdownIsPausedExtendedAndRemovedWithoutTouchingTheOthers() {
        var board = TimerBoard()
        let first = board.add(duration: 60, label: "a", at: at(0))!
        let second = board.add(duration: 60, label: "b", at: at(0))!
        board.pause(first, at: at(10))
        board.extend(second, by: 60, at: at(10))
        #expect(board.entries[0].timer.phase == .paused(remaining: 50))
        #expect(board.entries[1].timer.remaining(at: at(10)) == 110)
        board.resume(first, at: at(20))
        #expect(board.entries[0].timer.phase == .running(endsAt: at(70)))
        board.remove(first)
        #expect(board.entries.map(\.id) == [second])
    }

    @Test func aRemovedCountdownsPlaceIsFreeAndItsNumberIsNotUsedAgain() {
        var board = TimerBoard()
        let first = board.add(duration: 60, label: "", at: at(0))!
        board.remove(first)
        let next = board.add(duration: 60, label: "", at: at(0))!
        #expect(next != first)
        #expect(board.entries.count == 1)
    }
}

@Suite struct TimerLengthTests {
    @Test func aLengthIsReadAsHoursMinutesAndSeconds() {
        let length = TimerLength(seconds: 3_725)
        #expect(length.hours == 1 && length.minutes == 2 && length.seconds == 5)
        #expect(length.total == 3_725)
    }

    @Test func aLengthIsNeverNothingAndNeverPastThreeHours() {
        #expect(TimerLength(seconds: 0).total == 1)
        #expect(TimerLength(seconds: -5).total == 1)
        #expect(TimerLength(seconds: 99_999).total == 10_800)
    }

    @Test func eachWheelTurnsWithinItsOwnRange() {
        let length = TimerLength(seconds: 59 * 60 + 59)
        #expect(length.turning(.seconds, by: 1).total == 59 * 60 + 59)
        #expect(length.turning(.minutes, by: 1).total == 59 * 60 + 59)
        #expect(length.turning(.hours, by: 1).total == 3_600 + 59 * 60 + 59)
        #expect(length.turning(.minutes, by: -10).total == 49 * 60 + 59)
        #expect(TimerLength(seconds: 30).turning(.seconds, by: -45).total == 1)
        #expect(TimerLength(seconds: 3 * 3_600).turning(.minutes, by: 5).total == 10_800)
    }

    @Test func aWholeNumberOfMinutesCanBecomeAPreset() {
        #expect(TimerLength(seconds: 1_500).wholeMinutes == 25)
        #expect(TimerLength(seconds: 1_530).wholeMinutes == nil)
        #expect(TimerLength(seconds: 30).wholeMinutes == nil)
    }

    @Test func theLengthIsRememberedAndStartsFromTheOldMinutes() {
        let defaults = InMemoryDefaults()
        defaults.set(40, forKey: "timer.minutes")
        let store = TimerSettingsStore(defaults: defaults)
        #expect(store.seconds == 2_400)
        store.seconds = 95
        #expect(TimerSettingsStore(defaults: defaults).seconds == 95)
        store.seconds = 0
        #expect(store.seconds == 1)
    }
}
