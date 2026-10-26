import Foundation
import Testing
@testable import NotchCore

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func request(_ id: String, priority: Int = 1, duration: TimeInterval = 3) -> LiveActivityRequest {
    LiveActivityRequest(id: id, priority: priority, duration: duration)
}

@Suite struct LiveActivityQueueTests {
    @Test func idleQueueShowsNothing() {
        let queue = LiveActivityQueue()
        #expect(queue.current == nil)
        #expect(queue.nextDeadline == nil)
        #expect(queue.waitingIDs.isEmpty)
    }

    @Test func presentsImmediatelyWhenIdle() {
        var queue = LiveActivityQueue()
        queue.present(request("a"), at: at(0))
        #expect(queue.current?.id == "a")
        #expect(queue.nextDeadline == at(3))
    }

    @Test func expiresAfterDuration() {
        var queue = LiveActivityQueue()
        queue.present(request("a"), at: at(0))
        queue.advance(to: at(2.9))
        #expect(queue.current?.id == "a")
        queue.advance(to: at(3))
        #expect(queue.current == nil)
        #expect(queue.nextDeadline == nil)
    }

    @Test func sameIDRefreshesDeadlineAndContent() {
        var queue = LiveActivityQueue()
        queue.present(request("a", duration: 3), at: at(0))
        queue.present(request("a", duration: 5), at: at(2))
        #expect(queue.current == request("a", duration: 5))
        #expect(queue.nextDeadline == at(7))
        #expect(queue.waitingIDs.isEmpty)
    }

    @Test func higherPriorityReplacesCurrentForGood() {
        var queue = LiveActivityQueue()
        queue.present(request("low", priority: 1), at: at(0))
        queue.present(request("high", priority: 3), at: at(1))
        #expect(queue.current?.id == "high")
        #expect(queue.waitingIDs.isEmpty)
        queue.advance(to: at(4))
        #expect(queue.current == nil)
    }

    @Test func equalPriorityReplacesCurrent() {
        var queue = LiveActivityQueue()
        queue.present(request("a", priority: 2), at: at(0))
        queue.present(request("b", priority: 2), at: at(1))
        #expect(queue.current?.id == "b")
    }

    @Test func lowerPriorityWaitsThenShowsForItsFullDuration() {
        var queue = LiveActivityQueue()
        queue.present(request("high", priority: 3, duration: 4), at: at(0))
        queue.present(request("low", priority: 1, duration: 2), at: at(1))
        #expect(queue.current?.id == "high")
        #expect(queue.waitingIDs == ["low"])
        queue.advance(to: at(4))
        #expect(queue.current?.id == "low")
        #expect(queue.nextDeadline == at(6))
    }

    @Test func waitingOrderIsPriorityThenArrival() {
        var queue = LiveActivityQueue()
        queue.present(request("top", priority: 9), at: at(0))
        queue.present(request("p1-first", priority: 1), at: at(0))
        queue.present(request("p2", priority: 2), at: at(0))
        queue.present(request("p1-second", priority: 1), at: at(0))
        #expect(queue.waitingIDs == ["p2", "p1-first", "p1-second"])
    }

    @Test func waitingSameIDIsReplacedNotDuplicated() {
        var queue = LiveActivityQueue()
        queue.present(request("top", priority: 9), at: at(0))
        queue.present(request("w", priority: 1, duration: 2), at: at(0))
        queue.present(request("w", priority: 1, duration: 8), at: at(1))
        #expect(queue.waitingIDs == ["w"])
        queue.advance(to: at(3))
        #expect(queue.current == request("w", priority: 1, duration: 8))
    }

    @Test func fullWaitingListDropsLowestOldest() {
        var queue = LiveActivityQueue()
        queue.present(request("top", priority: 9), at: at(0))
        queue.present(request("a", priority: 1), at: at(0))
        queue.present(request("b", priority: 2), at: at(0))
        queue.present(request("c", priority: 1), at: at(0))
        queue.present(request("d", priority: 2), at: at(0))
        #expect(queue.waitingIDs == ["b", "d", "c"])
    }

    @Test func newcomerWithLowestPriorityIsDroppedWhenFull() {
        var queue = LiveActivityQueue()
        queue.present(request("top", priority: 9), at: at(0))
        queue.present(request("a", priority: 3), at: at(0))
        queue.present(request("b", priority: 3), at: at(0))
        queue.present(request("c", priority: 3), at: at(0))
        queue.present(request("d", priority: 1), at: at(0))
        #expect(queue.waitingIDs == ["a", "b", "c"])
    }

    @Test func dismissCurrentPromotesNext() {
        var queue = LiveActivityQueue()
        queue.present(request("high", priority: 3), at: at(0))
        queue.present(request("low", priority: 1, duration: 2), at: at(0))
        queue.dismiss(id: "high", at: at(1))
        #expect(queue.current?.id == "low")
        #expect(queue.nextDeadline == at(3))
    }

    @Test func dismissWaiting() {
        var queue = LiveActivityQueue()
        queue.present(request("high", priority: 3), at: at(0))
        queue.present(request("low", priority: 1), at: at(0))
        queue.dismiss(id: "low", at: at(1))
        #expect(queue.waitingIDs.isEmpty)
        #expect(queue.current?.id == "high")
    }

    @Test func dismissUnknownIsIgnored() {
        var queue = LiveActivityQueue()
        queue.present(request("a"), at: at(0))
        queue.dismiss(id: "zzz", at: at(1))
        #expect(queue.current?.id == "a")
    }

    @Test func lateAdvanceGivesTheNextItsFullDuration() {
        var queue = LiveActivityQueue()
        queue.present(request("high", priority: 3, duration: 1), at: at(0))
        queue.present(request("low", priority: 1, duration: 2), at: at(0))
        queue.advance(to: at(100))
        #expect(queue.current?.id == "low")
        #expect(queue.nextDeadline == at(102))
    }
}

/// Something that stays beside the notch for as long as it is true, such as "music is
/// playing": it shows whenever nothing timed does.
@Suite struct RestingActivityTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private let music = LiveActivityRequest(id: "media.playing", priority: 0, duration: 0)

    @Test func showsWhileNothingElseDoesAndNeverExpires() {
        var queue = LiveActivityQueue()
        queue.setResting(music)
        #expect(queue.current == music)
        #expect(queue.nextDeadline == nil)
        queue.advance(to: start.addingTimeInterval(3_600))
        #expect(queue.current == music)
    }

    @Test func givesWayToATimedActivityAndComesBackAfterIt() {
        var queue = LiveActivityQueue()
        queue.setResting(music)
        let alert = LiveActivityRequest(id: "capsLock", priority: 2, duration: 2)
        queue.present(alert, at: start)
        #expect(queue.current == alert)
        #expect(queue.nextDeadline == start.addingTimeInterval(2))
        queue.advance(to: start.addingTimeInterval(2))
        #expect(queue.current == music)
        #expect(queue.nextDeadline == nil)
    }

    @Test func evenTheLeastImportantTimedActivityShowsOverIt() {
        var queue = LiveActivityQueue()
        queue.setResting(LiveActivityRequest(id: "media.playing", priority: 9, duration: 0))
        let quiet = LiveActivityRequest(id: "copied", priority: 0, duration: 1)
        queue.present(quiet, at: start)
        #expect(queue.current == quiet)
    }

    @Test func goesAwayWhenClearedOrDismissed() {
        var queue = LiveActivityQueue()
        queue.setResting(music)
        queue.setResting(nil)
        #expect(queue.current == nil)
        queue.setResting(music)
        queue.dismiss(id: music.id, at: start)
        #expect(queue.current == nil)
    }

    @Test func settingItWhileATimedActivityShowsWaitsItsTurn() {
        var queue = LiveActivityQueue()
        let alert = LiveActivityRequest(id: "capsLock", priority: 2, duration: 2)
        queue.present(alert, at: start)
        queue.setResting(music)
        #expect(queue.current == alert)
        #expect(queue.restingID == music.id)
        queue.advance(to: start.addingTimeInterval(2))
        #expect(queue.current == music)
    }
}

@Suite struct HiddenActivityTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let music = LiveActivityRequest(id: "media.playing", priority: 0, duration: 0)

    @Test func hidingATimedActivityShowsWhatWaitsBehindIt() {
        var queue = LiveActivityQueue()
        queue.setResting(music)
        queue.present(LiveActivityRequest(id: "timer", priority: 1, duration: 5), at: now)
        queue.hideCurrent(at: now)
        #expect(queue.current?.id == "media.playing")
        #expect(queue.nextDeadline == nil)
    }

    @Test func hidingTheRestingActivityLeavesTheNotchBare() {
        var queue = LiveActivityQueue()
        queue.setResting(music)
        queue.hideCurrent(at: now)
        #expect(queue.current == nil)
        // The track changing refreshes the same activity: it stays out of sight.
        queue.setResting(music)
        #expect(queue.current == nil)
        // Something timed still shows, and the notch is bare again after it.
        queue.present(LiveActivityRequest(id: "timer", priority: 1, duration: 5), at: now)
        #expect(queue.current?.id == "timer")
        queue.advance(to: now.addingTimeInterval(6))
        #expect(queue.current == nil)
    }

    @Test func aHiddenRestingActivityComesBackWhenAskedOrWhenItIsAnotherOne() {
        var queue = LiveActivityQueue()
        queue.setResting(music)
        queue.hideCurrent(at: now)
        queue.unhideResting()
        #expect(queue.current?.id == "media.playing")

        queue.hideCurrent(at: now)
        queue.setResting(LiveActivityRequest(id: "call", priority: 0, duration: 0))
        #expect(queue.current?.id == "call")
    }

    @Test func hidingWithNothingShowingDoesNothing() {
        var queue = LiveActivityQueue()
        queue.hideCurrent(at: now)
        #expect(queue.current == nil)
        queue.setResting(music)
        #expect(queue.current?.id == "media.playing")
    }
}
