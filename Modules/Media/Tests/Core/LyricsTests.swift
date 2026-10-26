import Foundation
import Testing
@testable import MediaCore

@Suite struct LyricsTests {
    private let sample = """
    [ti:Blinding Lights]
    [00:13.50] Yeah
    [00:27.00]I've been tryna call
    [01:05.25] I said, ooh, I'm blinded by the lights

    [01:12.00]
    not a timed line
    """

    @Test func readsTimedLinesAndSkipsEverythingElse() {
        let lyrics = Lyrics(synced: sample)
        #expect(lyrics.lines.map(\.text) == ["Yeah", "I've been tryna call", "I said, ooh, I'm blinded by the lights", ""])
        #expect(lyrics.lines.map(\.time) == [13.5, 27, 65.25, 72])
    }

    @Test func aLineWithSeveralTimesIsSungAtEachOfThem() {
        let lyrics = Lyrics(synced: "[00:10.00][00:30.00] Again\n[00:20.00] Between")
        #expect(lyrics.lines.map(\.text) == ["Again", "Between", "Again"])
        #expect(lyrics.lines.map(\.time) == [10, 20, 30])
    }

    @Test func theLineBeingSungIsTheLastOneThatHasStarted() {
        let lyrics = Lyrics(synced: sample)
        #expect(lyrics.line(at: 5) == nil)
        #expect(lyrics.line(at: 13.5)?.text == "Yeah")
        #expect(lyrics.line(at: 40)?.text == "I've been tryna call")
        #expect(lyrics.line(at: 70)?.text == "I said, ooh, I'm blinded by the lights")
        // A timed empty line is a pause: nothing is being sung.
        #expect(lyrics.line(at: 80)?.text == "")
        #expect(lyrics.next(after: 40)?.text == "I said, ooh, I'm blinded by the lights")
        #expect(lyrics.next(after: 100) == nil)
    }

    @Test func noTimedLinesMeansNoLyrics() {
        #expect(Lyrics(synced: "just words\nno times").lines.isEmpty)
        #expect(Lyrics(synced: "").lines.isEmpty)
    }

    @Test func asksTheLyricsServiceForATrackByItsNameArtistAndLength() throws {
        let request = try #require(LyricsService.request(title: "Blinding Lights", artist: "The Weeknd", album: "After Hours", duration: 200.4))
        let url = try #require(request.url)
        #expect(url.host == "lrclib.net")
        #expect(url.path == "/api/get")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.contains(URLQueryItem(name: "track_name", value: "Blinding Lights")))
        #expect(items.contains(URLQueryItem(name: "artist_name", value: "The Weeknd")))
        #expect(items.contains(URLQueryItem(name: "album_name", value: "After Hours")))
        #expect(items.contains(URLQueryItem(name: "duration", value: "200")))
        // The service asks to be told who is calling.
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("AraNotch") == true)
    }

    @Test func aTrackWithNoNameOrNoArtistIsNotAskedFor() {
        #expect(LyricsService.request(title: "", artist: "The Weeknd", album: nil, duration: 200) == nil)
        #expect(LyricsService.request(title: "Blinding Lights", artist: nil, album: nil, duration: 200) == nil)
        #expect(LyricsService.request(title: "Blinding Lights", artist: " ", album: nil, duration: nil) == nil)
    }

    @Test func readsTheTimedLyricsOutOfTheAnswer() {
        let json = #"{"id":1,"trackName":"x","instrumental":false,"plainLyrics":"Yeah","syncedLyrics":"[00:13.50] Yeah\n[00:27.00] Call"}"#
        let lyrics = LyricsService.lyrics(from: Data(json.utf8))
        #expect(lyrics?.lines.map(\.text) == ["Yeah", "Call"])
    }

    @Test func anAnswerWithoutTimedLyricsGivesNone() {
        #expect(LyricsService.lyrics(from: Data(#"{"instrumental":true,"syncedLyrics":null}"#.utf8)) == nil)
        #expect(LyricsService.lyrics(from: Data(#"{"plainLyrics":"Yeah","syncedLyrics":""}"#.utf8)) == nil)
        #expect(LyricsService.lyrics(from: Data("not json".utf8)) == nil)
    }

    @Test func lyricsAreOffUntilTheUserTurnsThemOn() {
        let defaults = InMemoryDefaults()
        let store = MediaSettingsStore(defaults: defaults)
        // The track's name and artist leave the Mac to fetch them, so it is a choice.
        #expect(store.showsLyrics == false)
        store.showsLyrics = true
        #expect(MediaSettingsStore(defaults: defaults).showsLyrics == true)
    }
}
