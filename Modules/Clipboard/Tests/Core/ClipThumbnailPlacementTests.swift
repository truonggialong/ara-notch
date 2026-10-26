import Foundation
import Testing
@testable import ClipboardCore

@Suite struct ClipThumbnailPlacementTests {
    /// The picture area of a card at the regular notch size.
    private let frame = CGSize(width: 116, height: 64)

    @Test func aPictureIsShownWholeWhateverItsShape() {
        // A nearly square cut-out, a wide screenshot and a phone screenshot.
        #expect(ClipThumbnailPlacement(pictureSize: CGSize(width: 409, height: 383), in: frame) == .whole)
        #expect(ClipThumbnailPlacement(pictureSize: CGSize(width: 3024, height: 1964), in: frame) == .whole)
        #expect(ClipThumbnailPlacement(pictureSize: CGSize(width: 1170, height: 2532), in: frame) == .whole)
    }

    @Test func aVeryLongPageStartsAtItsTopInsteadOfShrinkingToASliver() {
        #expect(ClipThumbnailPlacement(pictureSize: CGSize(width: 800, height: 9000), in: frame) == .filledFromTop)
    }

    @Test func aVeryWideStripStartsAtItsLeadingEdge() {
        #expect(ClipThumbnailPlacement(pictureSize: CGSize(width: 9000, height: 300), in: frame) == .filledFromLeading)
    }

    @Test func aPictureWithoutASizeIsShownWhole() {
        #expect(ClipThumbnailPlacement(pictureSize: .zero, in: frame) == .whole)
        #expect(ClipThumbnailPlacement(pictureSize: CGSize(width: 10, height: 10), in: .zero) == .whole)
    }
}
