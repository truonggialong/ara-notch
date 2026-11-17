import Foundation
import Testing
@testable import SystemEventsCore

@Suite struct KeepAwakeTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func aClickStepsThroughTheLengthsAndBackToOff() {
        let first = KeepAwakeSession.next(after: nil, now: now)
        #expect(first?.ends == now.addingTimeInterval(30 * 60))
        let second = KeepAwakeSession.next(after: first, now: now)
        #expect(second?.ends == now.addingTimeInterval(60 * 60))
        let third = KeepAwakeSession.next(after: second, now: now)
        #expect(third?.ends == now.addingTimeInterval(120 * 60))
        let endless = KeepAwakeSession.next(after: third, now: now)
        #expect(endless?.ends == nil)
        #expect(endless?.remaining(at: now) == 1)
        #expect(KeepAwakeSession.next(after: endless, now: now) == nil)
    }

    @Test func aSessionPartWayThroughGoesOnToTheNextLength() {
        let running = KeepAwakeSession(ends: now.addingTimeInterval(40 * 60))
        #expect(KeepAwakeSession.next(after: running, now: now)?.ends == now.addingTimeInterval(120 * 60))
    }

    @Test func whatIsLeftReadsAtAGlance() {
        #expect(KeepAwakeSession(ends: now.addingTimeInterval(105 * 60)).left(at: now) == "1:45")
        #expect(KeepAwakeSession(ends: now.addingTimeInterval(28 * 60 + 10)).left(at: now) == "29\u{2032}")
        #expect(KeepAwakeSession(ends: nil).left(at: now) == "∞")
        #expect(KeepAwakeSession(ends: now).isOver(at: now))
        #expect(!KeepAwakeSession(ends: nil).isOver(at: now))
    }

    @Test func theRingEmptiesAsTheTimeRunsOut() {
        let session = KeepAwakeSession.next(after: nil, now: now)!
        #expect(session.remaining(at: now) == 1)
        #expect(session.remaining(at: now.addingTimeInterval(15 * 60)) == 0.5)
        #expect(session.remaining(at: now.addingTimeInterval(99 * 60)) == 0)
    }
}
