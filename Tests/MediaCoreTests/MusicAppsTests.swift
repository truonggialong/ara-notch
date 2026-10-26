import Testing
@testable import MediaCore

@Suite struct MusicAppsTests {
    @Test func onlyInstalledAppsAreOfferedInTheListsOrder() {
        let offered = MusicApps.offered(installed: ["com.apple.Music", "org.videolan.vlc", "com.spotify.client", "com.other.app"])
        #expect(offered == ["com.spotify.client", "org.videolan.vlc", "com.apple.Music"])
    }

    @Test func atMostFourAreOffered() {
        let offered = MusicApps.offered(installed: Set(MusicApps.known))
        #expect(offered.count == 4)
        #expect(offered.first == "com.spotify.client")
    }

    @Test func nothingIsOfferedWhenNoneIsInstalled() {
        #expect(MusicApps.offered(installed: []).isEmpty)
    }
}
