import CoreGraphics
import Foundation
import Testing
@testable import CaptureFeature

@Suite struct CaptureImageTests {
    /// A picture large enough that it is not read in one go when the file is opened.
    private func makePicture(side: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Stripes of changing colour, so the file does not compress to almost nothing.
        for row in 0..<side {
            context.setFillColor(CGColor(
                red: CGFloat(row % 251) / 251, green: CGFloat(row % 127) / 127, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: row, width: side, height: 1))
        }
        return try #require(context.makeImage())
    }

    private func alpha(of image: CGImage) throws -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return pixel[3]
    }

    @Test func aLoadedPictureOutlivesItsFile() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-test-\(UUID().uuidString).png")
        let data = try #require(CaptureImage.pngData(try makePicture(side: 1600)))
        try data.write(to: file)

        let loaded = try #require(CaptureImage.load(file))
        // The capture's temporary file is removed as soon as the picture is loaded.
        try FileManager.default.removeItem(at: file)

        #expect(loaded.width == 1600)
        #expect(try alpha(of: loaded) == 255)
    }
}
