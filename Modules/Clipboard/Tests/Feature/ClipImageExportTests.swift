import AppKit
import Foundation
import Testing
@testable import ClipboardFeature

@Suite struct ClipImageExportTests {
    /// A small opaque picture, as PNG data.
    private func makePNG() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    private func size(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    @Test func writesAJPEG() throws {
        let data = try #require(ClipImageExport.data(from: try makePNG(), format: "jpeg"))
        // JPEG files start with FF D8.
        #expect(data.prefix(2) == Data([0xFF, 0xD8]))
        #expect(size(of: data) == CGSize(width: 40, height: 30))
    }

    @Test func writesAHEIC() throws {
        let data = try #require(ClipImageExport.data(from: try makePNG(), format: "heic"))
        // An ISO media file: "ftyp" at byte 4.
        #expect(data.subdata(in: 4..<8) == Data("ftyp".utf8))
        #expect(size(of: data) == CGSize(width: 40, height: 30))
    }

    @Test func writesAPNG() throws {
        let data = try #require(ClipImageExport.data(from: try makePNG(), format: "png"))
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func refusesAnUnknownFormatAndDataThatIsNoPicture() throws {
        #expect(ClipImageExport.data(from: try makePNG(), format: "bmp") == nil)
        #expect(ClipImageExport.data(from: Data("not a picture".utf8), format: "png") == nil)
    }
}
