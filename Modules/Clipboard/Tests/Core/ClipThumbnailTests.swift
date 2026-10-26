import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardCore

/// A PNG of the given size, filled with one colour.
private func png(width: Int, height: Int) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

@Suite struct ClipThumbnailTests {
    @Test func aLargePictureIsShownFromASmallCopyKeepingItsShape() throws {
        // A screenshot of this Mac's display: about 24 MB once decoded at full size.
        let thumbnail = try #require(ClipThumbnail.image(from: try png(width: 3024, height: 1964)))
        #expect(thumbnail.width == ClipThumbnail.maxPixelSize)
        #expect(thumbnail.height == 665)
        #expect(ClipThumbnail.cost(of: thumbnail) < 3_000_000)
    }

    @Test func aTallPictureIsLimitedByItsHeight() throws {
        let thumbnail = try #require(ClipThumbnail.image(from: try png(width: 500, height: 4000)))
        #expect(thumbnail.height == ClipThumbnail.maxPixelSize)
        #expect(thumbnail.width == 128)
    }

    @Test func aCardTakesAnEvenSmallerCopy() throws {
        // A card is a few hundred points wide at most; the large preview takes the larger copy.
        let thumbnail = try #require(ClipThumbnail.image(
            from: try png(width: 3024, height: 1964), maxPixelSize: ClipThumbnail.cardPixelSize))
        #expect(thumbnail.width == 512)
        #expect(ClipThumbnail.cardPixelSize < ClipThumbnail.maxPixelSize)
    }

    @Test func aSmallPictureIsNotEnlarged() throws {
        let thumbnail = try #require(ClipThumbnail.image(from: try png(width: 200, height: 100)))
        #expect(thumbnail.width == 200)
        #expect(thumbnail.height == 100)
    }

    @Test func dataThatIsNoPictureGivesNone() {
        #expect(ClipThumbnail.image(from: Data("not a picture".utf8)) == nil)
    }
}
