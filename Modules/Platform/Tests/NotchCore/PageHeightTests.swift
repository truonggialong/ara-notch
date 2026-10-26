import CoreGraphics
import Testing
@testable import NotchCore

@Suite struct PageHeightTests {
    @Test func aPageThatAsksForNothingGetsTheUsualHeight() {
        #expect(PageHeight.open(sheetHeight: nil, size: .regular, screenHeight: 982) == NotchSize.regular.openSize.height)
    }

    @Test func aTallerPageIsEnlargedLikeTheRestOfTheNotch() {
        // 300 points of sheet at 110%.
        #expect(PageHeight.open(sheetHeight: 300, size: .regular, screenHeight: 982) == 330)
    }

    @Test func aPageIsNeverShorterThanUsualNorTallerThanMostOfTheScreen() {
        #expect(PageHeight.open(sheetHeight: 50, size: .regular, screenHeight: 982) == NotchSize.regular.openSize.height)
        #expect(PageHeight.open(sheetHeight: 5_000, size: .regular, screenHeight: 1_000) == 800)
        // A screen so low that the usual height is already more than its share keeps the usual height.
        #expect(PageHeight.open(sheetHeight: 400, size: .extraLarge, screenHeight: 300) == NotchSize.extraLarge.openSize.height)
    }
}
