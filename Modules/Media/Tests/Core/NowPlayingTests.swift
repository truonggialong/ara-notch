import Foundation
import Testing
@testable import MediaCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct NowPlayingParserTests {
    @Test func readsAPlayingTrack() throws {
        let line = #"{"bundleID":"com.apple.Music","isPlaying":true,"title":"Nắng ấm xa dần","artist":"Sơn Tùng","album":"m-tp","duration":215.5,"elapsed":12.25,"rate":1,"timestamp":1000,"artworkID":"abc","artwork":"AQID"}"#
        let update = try #require(NowPlayingParser.parse(line: line))
        #expect(update.track == NowPlaying(
            bundleID: "com.apple.Music", title: "Nắng ấm xa dần", artist: "Sơn Tùng", album: "m-tp",
            duration: 215.5, elapsed: 12.25, rate: 1, timestamp: date(1000), isPlaying: true, artworkID: "abc"))
        #expect(update.artwork == Data([1, 2, 3]))
        #expect(update.isUnavailable == false)
    }

    @Test func emptyStringsAndNullsBecomeNil() throws {
        let line = #"{"bundleID":"x","isPlaying":false,"title":"Bài","artist":"","album":null,"duration":null,"elapsed":null,"rate":0,"timestamp":null,"artworkID":""}"#
        let track = try #require(NowPlayingParser.parse(line: line)?.track)
        #expect(track.artist == nil)
        #expect(track.album == nil)
        #expect(track.duration == nil)
        #expect(track.timestamp == nil)
        #expect(track.artworkID == nil)
        #expect(track.isPlaying == false)
    }

    @Test(arguments: [#"{"isPlaying":false}"#, #"{"bundleID":"x","isPlaying":false,"title":""}"#, #"{"isPlaying":true,"title":null}"#])
    func withoutATitleThereIsNoTrack(_ line: String) throws {
        let update = try #require(NowPlayingParser.parse(line: line))
        #expect(update.track == nil)
        #expect(update.artwork == nil)
    }

    @Test func reportsThatTheSystemInterfaceIsMissing() throws {
        let update = try #require(NowPlayingParser.parse(line: #"{"unavailable":true}"#))
        #expect(update.isUnavailable)
        #expect(update.track == nil)
    }

    @Test(arguments: ["", "xin chào", "[1,2]", "{\"title\": "])
    func ignoresLinesThatAreNotAnUpdate(_ line: String) {
        #expect(NowPlayingParser.parse(line: line) == nil)
    }
}

@Suite struct NowPlayingPositionTests {
    private func track(elapsed: TimeInterval? = 10, rate: Double = 1, isPlaying: Bool = true,
                       duration: TimeInterval? = 100, timestamp: Date? = date(1000)) -> NowPlaying {
        NowPlaying(bundleID: nil, title: "t", artist: nil, album: nil, duration: duration, elapsed: elapsed,
                   rate: rate, timestamp: timestamp, isPlaying: isPlaying, artworkID: nil)
    }

    @Test func aPlayingTrackAdvancesWithTheClock() {
        #expect(track().position(at: date(1030)) == 40)
        #expect(track(rate: 2).position(at: date(1005)) == 20)
    }

    @Test func aPausedTrackStaysWhereItWas() {
        #expect(track(rate: 0, isPlaying: false).position(at: date(5000)) == 10)
        // Some players leave the rate at 1 while paused.
        #expect(track(rate: 1, isPlaying: false).position(at: date(5000)) == 10)
    }

    @Test func thePositionStaysInsideTheTrack() {
        #expect(track().position(at: date(9999)) == 100)
        #expect(track().position(at: date(900)) == 10)
        #expect(track(duration: nil).position(at: date(2000)) == 1010)
    }

    @Test func withoutAReferenceTimeThePositionIsTheReportedOne() {
        #expect(track(timestamp: nil).position(at: date(2000)) == 10)
        #expect(track(elapsed: nil).position(at: date(2000)) == nil)
    }

    @Test func progressIsAFractionOfTheDuration() {
        #expect(track().progress(at: date(1040)) == 0.5)
        #expect(track(duration: nil).progress(at: date(1040)) == nil)
        #expect(track(duration: 0).progress(at: date(1040)) == nil)
    }

    @Test func clockFormatsMinutesAndHours() {
        #expect(NowPlaying.clock(0) == "0:00")
        #expect(NowPlaying.clock(65.9) == "1:05")
        #expect(NowPlaying.clock(3725) == "1:02:05")
        #expect(NowPlaying.clock(-3) == "0:00")
    }

    @Test func aChangeOfTitleArtistOrAlbumIsAnotherTrack() {
        let first = track()
        var second = first
        second.elapsed = 55
        #expect(first.isSameTrack(as: second))
        second.title = "khác"
        #expect(!first.isSameTrack(as: second))
    }
}

@Suite struct MediaSettingsStoreTests {
    @Test func everythingIsOnByDefaultAndIsRemembered() {
        let defaults = InMemoryDefaults()
        let store = MediaSettingsStore(defaults: defaults)
        #expect(store.isEnabled == true)
        #expect(store.announcesTracks == true)
        store.isEnabled = false
        store.announcesTracks = false
        let reopened = MediaSettingsStore(defaults: defaults)
        #expect(reopened.isEnabled == false)
        #expect(reopened.announcesTracks == false)
    }

    @Test func theIndicatorWhilePlayingIsOnUntilTurnedOff() {
        let defaults = InMemoryDefaults()
        let store = MediaSettingsStore(defaults: defaults)
        #expect(store.showsWhilePlaying == true)
        store.showsWhilePlaying = false
        #expect(MediaSettingsStore(defaults: defaults).showsWhilePlaying == false)
    }

    @Test func commandCodesMatchTheSystemInterface() {
        #expect(MediaCommand.play.rawValue == 0)
        #expect(MediaCommand.pause.rawValue == 1)
        #expect(MediaCommand.togglePlayPause.rawValue == 2)
        #expect(MediaCommand.nextTrack.rawValue == 4)
        #expect(MediaCommand.previousTrack.rawValue == 5)
    }
}

@Suite struct NowPlayingUntitledTests {
    @Test func aTrackWithoutATitleIsCalledAfterItsFile() throws {
        // What QuickTime Player reports for a plain audio file: no title, only where it is.
        let line = #"{"bundleID":"com.apple.QuickTimePlayerX","isPlaying":true,"title":null,"file":"Bản thu thử.wav","duration":120,"elapsed":0,"rate":1}"#
        let track = try #require(NowPlayingParser.parse(line: line)?.track)
        #expect(track.title == "Bản thu thử")
        #expect(track.isPlaying)
    }

    @Test func aTitleWinsOverTheFileName() throws {
        let line = #"{"isPlaying":true,"title":"Bài","file":"track01.m4a"}"#
        #expect(try #require(NowPlayingParser.parse(line: line)?.track).title == "Bài")
    }

    @Test func somethingPlayingWithNoNameAtAllIsStillShown() throws {
        // A web video without a title: the page names the app instead, so the track has no title of its own.
        let line = #"{"bundleID":"com.google.Chrome","isPlaying":true,"title":null,"file":"","duration":95,"elapsed":3,"rate":1}"#
        let track = try #require(NowPlayingParser.parse(line: line)?.track)
        #expect(track.title == "")
        #expect(track.bundleID == "com.google.Chrome")
    }

    @Test func aNamelessThingThatIsNotPlayingIsNotShown() throws {
        let update = try #require(NowPlayingParser.parse(line: #"{"bundleID":"com.google.Chrome","isPlaying":false,"title":null}"#))
        #expect(update.track == nil)
    }

    @Test func withoutAnAppOrAName_thereIsNothingToShow() throws {
        let update = try #require(NowPlayingParser.parse(line: #"{"isPlaying":true,"title":null,"file":""}"#))
        #expect(update.track == nil)
    }
}

@Suite struct SoundingAppsTests {
    @Test func aHelperCountsAsTheAppItBelongsTo() {
        #expect(SoundingApps.owner(ofBundleID: "com.google.Chrome.helper") == "com.google.Chrome")
        #expect(SoundingApps.owner(ofBundleID: "com.microsoft.edgemac.helper.renderer") == "com.microsoft.edgemac")
        #expect(SoundingApps.owner(ofBundleID: "com.anthropic.claudefordesktop.helper") == "com.anthropic.claudefordesktop")
        #expect(SoundingApps.owner(ofBundleID: "com.spotify.client") == "com.spotify.client")
        #expect(SoundingApps.owner(ofBundleID: "com.vng.zalo.zalocall") == "com.vng.zalo.zalocall")
    }

    @Test func listsEachAppOnceInASteadyOrder() {
        let apps = SoundingApps.others(
            sounding: ["com.tdesktop.Telegram", "com.google.Chrome", "com.google.Chrome"], playingBundleID: nil, own: "com.aranotch.app")
        #expect(apps == ["com.google.Chrome", "com.tdesktop.Telegram"])
    }

    @Test func leavesOutTheAppThePageAlreadyShowsAndThisAppItself() {
        let apps = SoundingApps.others(
            sounding: ["com.spotify.client", "com.aranotch.app", "com.tdesktop.Telegram"],
            playingBundleID: "com.spotify.client", own: "com.aranotch.app")
        #expect(apps == ["com.tdesktop.Telegram"])
    }

    @Test func aSoundMustLastBeforeItCounts() {
        var filter = SoundDebounce()
        // A notification blip: on at 10.0, off at 10.4.
        filter.update(sounding: ["com.tdesktop.Telegram"], at: date(10))
        #expect(filter.steady(at: date(10.4)).isEmpty)
        filter.update(sounding: [], at: date(10.4))
        #expect(filter.steady(at: date(13)).isEmpty)
        // A video: still on two seconds later.
        filter.update(sounding: ["com.google.Chrome"], at: date(20))
        #expect(filter.steady(at: date(20 + SoundDebounce.minimum)) == ["com.google.Chrome"])
        #expect(filter.nextCheck(after: date(20)) == date(20 + SoundDebounce.minimum))
    }

    @Test func aSoundThatPausesBrieflyKeepsItsPlace() {
        var filter = SoundDebounce()
        filter.update(sounding: ["com.google.Chrome"], at: date(20))
        filter.update(sounding: [], at: date(30))
        // Between two clips: gone for a moment, back before the grace time is over.
        #expect(filter.steady(at: date(30.5)) == ["com.google.Chrome"])
        #expect(filter.steady(at: date(30 + SoundDebounce.grace + 0.1)).isEmpty)
    }
}

@Suite struct NowPlayingSeekTests {
    private func track(duration: TimeInterval? = 200) -> NowPlaying {
        NowPlaying(
            bundleID: nil, title: "Bài", artist: nil, album: nil, duration: duration, elapsed: 10, rate: 1,
            timestamp: date(1000), isPlaying: true, artworkID: nil)
    }

    @Test func seekingMovesThePositionAndRestartsItsClock() throws {
        let seek = try #require(track().seeking(toFraction: 0.5, at: date(1030)))
        #expect(seek.seconds == 100)
        #expect(seek.track.elapsed == 100)
        #expect(seek.track.timestamp == date(1030))
        #expect(seek.track.position(at: date(1040)) == 110)
    }

    @Test func seekingStaysInsideTheTrack() throws {
        #expect(try #require(track().seeking(toFraction: -1, at: date(1030))).seconds == 0)
        #expect(try #require(track().seeking(toFraction: 2, at: date(1030))).seconds == 200)
    }

    @Test func aTrackOfUnknownLengthCannotBeSought() {
        #expect(track(duration: nil).seeking(toFraction: 0.5, at: date(1030)) == nil)
        #expect(track(duration: 0).seeking(toFraction: 0.5, at: date(1030)) == nil)
    }
}

@Suite struct NowPlayingViewChoiceTests {
    @Test func aPlayingTrackIsShown() {
        #expect(NowPlayingView.choose(hasTrack: true, trackIsPlaying: true, soundingApps: 2) == .track)
    }

    @Test func appsThatAreSoundingComeBeforeATrackThatIsPaused() {
        // The system still names a clip paused long ago while another app is the one playing.
        #expect(NowPlayingView.choose(hasTrack: true, trackIsPlaying: false, soundingApps: 1) == .soundingApps)
    }

    @Test func aPausedTrackIsShownWhenNothingElseSounds() {
        #expect(NowPlayingView.choose(hasTrack: true, trackIsPlaying: false, soundingApps: 0) == .track)
    }

    @Test func soundWithoutATrackShowsTheApps() {
        #expect(NowPlayingView.choose(hasTrack: false, trackIsPlaying: false, soundingApps: 1) == .soundingApps)
    }

    @Test func silenceShowsNothing() {
        #expect(NowPlayingView.choose(hasTrack: false, trackIsPlaying: false, soundingApps: 0) == .nothing)
    }
}

@Suite struct HelperRestartsTests {
    @Test func aHelperThatKeepsExitingIsRestartedAFewTimesThenGivenUp() {
        var restarts = HelperRestarts(limit: 3)
        #expect(restarts.afterExit() == .restart)
        #expect(restarts.afterExit() == .restart)
        #expect(restarts.afterExit() == .restart)
        // Then it is left alone, and the page says the player cannot be read.
        #expect(restarts.afterExit() == .giveUp)
        #expect(restarts.afterExit() == .giveUp)
    }

    @Test func aHelperThatCannotStartAtAllIsGivenUpAtOnce() {
        var restarts = HelperRestarts(limit: 3)
        #expect(restarts.afterFailedStart() == .giveUp)
    }
}
