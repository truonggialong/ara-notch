import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ClipboardCore

private func picture(width: Int, height: Int, photoLike: Bool, transparent: Bool = false, as type: String) throws -> Data {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if photoLike, let pixels = context.data {
        // Detail in every pixel, as in a photo: PNG keeps it all and is large.
        let bytes = pixels.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        var generator = SystemRandomNumberGenerator()
        for row in 0..<height {
            for column in 0..<width {
                let pixel = bytes + row * context.bytesPerRow + column * 4
                let value = generator.next()
                pixel[0] = UInt8(truncatingIfNeeded: value)
                pixel[1] = UInt8(truncatingIfNeeded: value >> 8)
                pixel[2] = UInt8(truncatingIfNeeded: value >> 16)
                pixel[3] = 255
            }
        }
    }
    if transparent {
        context.clear(CGRect(x: 0, y: 0, width: width / 4, height: height / 4))
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func type(of data: Data) -> String? {
    CGImageSourceCreateWithData(data as CFData, nil).flatMap(CGImageSourceGetType) as String?
}

@Suite struct ClipImageDataTests {
    @Test func aSmallPNGIsKeptByteForByte() throws {
        let png = try picture(width: 300, height: 200, photoLike: false, as: "public.png")
        #expect(ClipImageData.stored(from: png) == png)
    }

    @Test func aScreenshotCopiedAsTIFFIsKeptAsPNG() throws {
        let tiff = try picture(width: 600, height: 400, photoLike: false, as: "public.tiff")
        let stored = try #require(ClipImageData.stored(from: tiff))
        #expect(type(of: stored) == "public.png")
    }

    @Test func aLargePhotoIsKeptAsHEICFarSmallerThanPNG() throws {
        let tiff = try picture(width: 1800, height: 1400, photoLike: true, as: "public.tiff")
        let stored = try #require(ClipImageData.stored(from: tiff))
        #expect(type(of: stored) == "public.heic")
        #expect(stored.count < ClipImageData.largePNGBytes)
    }

    @Test func aLargePictureWithTransparencyStaysPNG() throws {
        let tiff = try picture(width: 1800, height: 1400, photoLike: true, transparent: true, as: "public.tiff")
        let stored = try #require(ClipImageData.stored(from: tiff))
        #expect(type(of: stored) == "public.png")
    }

    @Test func storedPicturesAreNamedAfterTheirFormat() throws {
        let png = try picture(width: 10, height: 10, photoLike: false, as: "public.png")
        let heic = try picture(width: 64, height: 64, photoLike: true, as: "public.heic")
        #expect(ClipImageData.fileExtension(of: png) == "png")
        #expect(ClipImageData.fileExtension(of: heic) == "heic")
        #expect(ClipImageData.typeIdentifier(of: heic) == "public.heic")
    }

    @Test func somethingThatIsNotAPictureIsRefused() {
        #expect(ClipImageData.stored(from: Data("không phải ảnh".utf8)) == nil)
    }
}
