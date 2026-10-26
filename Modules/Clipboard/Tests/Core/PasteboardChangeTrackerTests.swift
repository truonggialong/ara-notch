import Testing
@testable import ClipboardCore

@Suite struct PasteboardChangeTrackerTests {
    @Test func unchangedCountNeedsNoRead() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        let read1 = tracker.shouldRead(changeCount: 5)
        #expect(!read1)
    }

    @Test func changedCountNeedsARead() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        let read2 = tracker.shouldRead(changeCount: 6)
        #expect(read2)
        tracker.readFinished(foundContent: true)
        let read3 = tracker.shouldRead(changeCount: 6)
        #expect(!read3)
    }

    @Test func emptyReadIsRetriedTwiceThenGivenUp() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        let read4 = tracker.shouldRead(changeCount: 6)
        #expect(read4)
        tracker.readFinished(foundContent: false)
        let read5 = tracker.shouldRead(changeCount: 6)
        #expect(read5)
        tracker.readFinished(foundContent: false)
        let read6 = tracker.shouldRead(changeCount: 6)
        #expect(read6)
        tracker.readFinished(foundContent: false)
        let read7 = tracker.shouldRead(changeCount: 6)
        #expect(!read7)
    }

    @Test func retryStopsOnceContentIsFound() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        let read8 = tracker.shouldRead(changeCount: 6)
        #expect(read8)
        tracker.readFinished(foundContent: false)
        let read9 = tracker.shouldRead(changeCount: 6)
        #expect(read9)
        tracker.readFinished(foundContent: true)
        let read10 = tracker.shouldRead(changeCount: 6)
        #expect(!read10)
    }

    @Test func newChangeRestartsTheRetryBudget() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        let read11 = tracker.shouldRead(changeCount: 6)
        #expect(read11)
        tracker.readFinished(foundContent: false)
        let read12 = tracker.shouldRead(changeCount: 6)
        #expect(read12)
        tracker.readFinished(foundContent: false)
        let read13 = tracker.shouldRead(changeCount: 7)
        #expect(read13)
        tracker.readFinished(foundContent: false)
        let read14 = tracker.shouldRead(changeCount: 7)
        #expect(read14)
        tracker.readFinished(foundContent: false)
        let read15 = tracker.shouldRead(changeCount: 7)
        #expect(read15)
        tracker.readFinished(foundContent: false)
        let read16 = tracker.shouldRead(changeCount: 7)
        #expect(!read16)
    }

    @Test func ignoringOwnWriteSuppressesTheRead() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        tracker.ignore(changeCount: 6)
        let read17 = tracker.shouldRead(changeCount: 6)
        #expect(!read17)
    }

    @Test func ignoringCancelsPendingRetries() {
        var tracker = PasteboardChangeTracker(changeCount: 5)
        let read18 = tracker.shouldRead(changeCount: 6)
        #expect(read18)
        tracker.readFinished(foundContent: false)
        tracker.ignore(changeCount: 7)
        let read19 = tracker.shouldRead(changeCount: 7)
        #expect(!read19)
    }
}
