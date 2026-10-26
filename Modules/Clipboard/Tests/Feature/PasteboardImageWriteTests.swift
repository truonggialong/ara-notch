import AppKit
import ClipboardCore
import ImageIO
import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct PasteboardImageWriteTests {
    private func heicPicture() throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.3, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func aPhotoKeptAsHEICIsPastedAsHEICPNGAndTIFF() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("aranotch-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let item = ClipItem(
            id: 1, kind: .image, text: "", blobName: "a.heic", source: ClipSource(bundleID: nil, appName: nil),
            createdAt: Date(), lastUsedAt: Date(), byteSize: 10)
        let heic = try heicPicture()
        #expect(PasteboardWriter.write(item, imageData: heic, to: pasteboard))
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.heic")) == heic)
        let png = try #require(pasteboard.data(forType: .png))
        #expect(ClipImageData.typeIdentifier(of: png) == "public.png")
        #expect(pasteboard.data(forType: .tiff) != nil)
    }
}
