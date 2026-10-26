import Foundation
import Testing
@testable import FilesCore

@Suite struct FileDropTileTests {
    @Test func theTilesAreOfferedInAFixedOrder() {
        #expect(FileDropTile.allCases == [.airDrop, .resize, .compress, .pdf])
    }

    @Test func eachTileButAirDropRunsAnActionOnWhatIsDropped() {
        #expect(FileDropTile.airDrop.action == nil)
        #expect(FileDropTile.resize.action == .resize(percent: 50))
        #expect(FileDropTile.compress.action == .compress)
        #expect(FileDropTile.pdf.action == .makePDF)
    }

    @Test func progressIsAWholePercentage() {
        #expect(FileProgress.percent(done: 0, total: 3) == 0)
        #expect(FileProgress.percent(done: 1, total: 3) == 33)
        #expect(FileProgress.percent(done: 2, total: 3) == 67)
        #expect(FileProgress.percent(done: 3, total: 3) == 100)
        // Nothing to do is not a division by zero, and more done than asked is still 100.
        #expect(FileProgress.percent(done: 0, total: 0) == 0)
        #expect(FileProgress.percent(done: 5, total: 3) == 100)
    }
}
