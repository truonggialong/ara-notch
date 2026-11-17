import Testing
@testable import FilesCore

@Suite struct DownloadsTests {
    @Test func oneDownloadShowsItsShare() {
        var tally = DownloadTally()
        tally.items["a"] = .init(name: "video.mp4", fraction: 0.645)
        #expect(tally.fraction == 0.645)
        #expect(tally.label == "64%")
    }

    @Test func severalCountTheSameAndUnknownSizesAsNotBegun() {
        var tally = DownloadTally()
        tally.items["a"] = .init(name: "a", fraction: 1)
        tally.items["b"] = .init(name: "b", fraction: nil)
        #expect(tally.fraction == 0.5)
        #expect(tally.label == "2 · 50%")
        #expect(DownloadTally().fraction == 0)
        #expect(DownloadTally().isEmpty)
    }
}
