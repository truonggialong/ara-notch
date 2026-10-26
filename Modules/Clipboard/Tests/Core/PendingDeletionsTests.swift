import Foundation
import Testing
@testable import ClipboardCore

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct PendingDeletionsTests {
    @Test func aDeletedClipIsHiddenAtOnceButNotYetGone() {
        var pending = PendingDeletions()
        pending.add([7], at: at(100))
        #expect(pending.hiddenIDs == [7])
        #expect(pending.takeDue(at: at(101)).isEmpty)
        #expect(pending.hiddenIDs == [7])
    }

    @Test func itIsReallyDeletedOnceTheTimeToUndoHasPassed() {
        var pending = PendingDeletions()
        pending.add([7], at: at(100))
        #expect(pending.takeDue(at: at(100 + PendingDeletions.window)) == [7])
        #expect(pending.hiddenIDs.isEmpty)
        #expect(pending.nextDeadline == nil)
    }

    @Test func undoBringsBackTheLastDeletion() {
        var pending = PendingDeletions()
        pending.add([7], at: at(100))
        pending.add([9], at: at(102))
        #expect(pending.undoLast() == [9])
        #expect(pending.hiddenIDs == [7])
        #expect(pending.undoLast() == [7])
        #expect(pending.undoLast().isEmpty)
    }

    @Test func clipsDeletedInOneGoComeBackInOneGo() {
        var pending = PendingDeletions()
        // The Library deletes a selection one clip after another, within the same moment.
        pending.add([3], at: at(100))
        pending.add([4], at: at(100.05))
        pending.add([5], at: at(100.1))
        #expect(pending.latestCount == 3)
        #expect(Set(pending.undoLast()) == [3, 4, 5])
    }

    @Test func theNextDeadlineIsTheOldestDeletions() {
        var pending = PendingDeletions()
        pending.add([1], at: at(100))
        pending.add([2], at: at(103))
        #expect(pending.nextDeadline == at(100 + PendingDeletions.window))
        #expect(pending.takeDue(at: at(100 + PendingDeletions.window)) == [1])
        #expect(pending.nextDeadline == at(103 + PendingDeletions.window))
    }

    @Test func everythingStillWaitingCanBeTakenAtOnce() {
        var pending = PendingDeletions()
        pending.add([1], at: at(100))
        pending.add([2], at: at(103))
        #expect(pending.takeAll() == [1, 2])
        #expect(pending.hiddenIDs.isEmpty)
    }

    @Test func aClipIsNotCountedTwice() {
        var pending = PendingDeletions()
        pending.add([1], at: at(100))
        pending.add([1], at: at(103))
        #expect(pending.takeAll() == [1])
    }
}
