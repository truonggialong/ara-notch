import Foundation
import Testing
@testable import MediaCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct PausedRestingTests {
    @Test func aPlayingTrackRests() {
        var resting = PausedResting()
        resting.update(isPlaying: true, at: date(0))
        #expect(resting.shows(at: date(0)))
        #expect(resting.hideDate == nil)
    }

    @Test func aPausedTrackStaysForFiveMinutes() {
        var resting = PausedResting()
        resting.update(isPlaying: true, at: date(0))
        resting.update(isPlaying: false, at: date(100))
        #expect(resting.shows(at: date(100)))
        #expect(resting.shows(at: date(399)))
        #expect(!resting.shows(at: date(400)))
        #expect(resting.hideDate == date(400))
    }

    @Test func laterReportsOfThePauseDoNotRestartTheWait() {
        var resting = PausedResting()
        resting.update(isPlaying: true, at: date(0))
        resting.update(isPlaying: false, at: date(100))
        resting.update(isPlaying: false, at: date(250))
        #expect(resting.hideDate == date(400))
    }

    @Test func playingAgainStartsOver() {
        var resting = PausedResting()
        resting.update(isPlaying: true, at: date(0))
        resting.update(isPlaying: false, at: date(100))
        resting.update(isPlaying: true, at: date(500))
        #expect(resting.shows(at: date(500)))
        resting.update(isPlaying: false, at: date(600))
        #expect(resting.shows(at: date(899)))
    }

    @Test func aTrackFoundPausedIsNotShown() {
        // Paused before the app was there to see it play: nothing was just playing.
        var resting = PausedResting()
        resting.update(isPlaying: false, at: date(0))
        #expect(!resting.shows(at: date(0)))
    }

    @Test func nothingPlayingForgetsThePause() {
        var resting = PausedResting()
        resting.update(isPlaying: true, at: date(0))
        resting.update(isPlaying: false, at: date(10))
        resting.reset()
        resting.update(isPlaying: false, at: date(20))
        #expect(!resting.shows(at: date(20)))
    }
}
