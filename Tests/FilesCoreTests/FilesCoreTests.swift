import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import FilesCore

private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-files-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

/// Writes a PNG with a colour gradient, optionally with a transparent corner.
@discardableResult
private func makePNG(
    _ url: URL, width: Int = 120, height: Int = 80, transparent: Bool = false, photoLike: Bool = false
) throws -> URL {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for x in 0..<width {
        context.setFillColor(CGColor(red: CGFloat(x) / CGFloat(width), green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: x, y: 0, width: 1, height: height))
    }
    if photoLike {
        // Fine detail everywhere, as in a photo: PNG keeps every pixel and is large.
        var generator = SystemRandomNumberGenerator()
        for y in stride(from: 0, to: height, by: 2) {
            for x in stride(from: 0, to: width, by: 2) {
                context.setFillColor(CGColor(
                    red: .random(in: 0...1, using: &generator), green: .random(in: 0...1, using: &generator),
                    blue: .random(in: 0...1, using: &generator), alpha: 1))
                context.fill(CGRect(x: x, y: y, width: 2, height: 2))
            }
        }
    }
    if transparent {
        context.clear(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
    }
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

private func fileSize(_ url: URL) throws -> Int {
    try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
}

private func hasAlpha(_ url: URL) -> Bool {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return false }
    return properties[kCGImagePropertyHasAlpha] as? Bool ?? false
}

private func typeIdentifier(of url: URL) -> String? {
    CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(CGImageSourceGetType) as String?
}

@Suite struct OutputNamingTests {
    @Test func putsTheResultNextToTheSource() {
        let source = URL(fileURLWithPath: "/tmp/ảnh chụp.png")
        let result = OutputNaming.destination(for: source, suffix: "-50", fileExtension: "jpg") { _ in false }
        #expect(result.path == "/tmp/ảnh chụp-50.jpg")
    }

    @Test func neverReusesAnExistingName() {
        let source = URL(fileURLWithPath: "/tmp/a.png")
        let taken: Set<String> = ["/tmp/a.jpg", "/tmp/a 2.jpg"]
        let result = OutputNaming.destination(for: source, suffix: "", fileExtension: "jpg") { taken.contains($0.path) }
        #expect(result.path == "/tmp/a 3.jpg")
    }

    @Test func canPlaceTheResultInAnotherFolder() {
        let source = URL(fileURLWithPath: "/readonly/a.png")
        let result = OutputNaming.destination(
            for: source, suffix: "", fileExtension: "pdf", in: URL(fileURLWithPath: "/Users/x/Downloads")) { _ in false }
        #expect(result.path == "/Users/x/Downloads/a.pdf")
    }

    @Test(arguments: ["a.png", "b.JPG", "c.jpeg", "d.heic", "e.tiff", "f.gif", "g.webp", "h.bmp"])
    func recognisesImagesByExtension(_ name: String) {
        #expect(FileActions.isImage(URL(fileURLWithPath: "/tmp/\(name)")))
    }

    @Test(arguments: ["a.pdf", "b.txt", "c", "d.png.zip"])
    func otherFilesAreNotImages(_ name: String) {
        #expect(!FileActions.isImage(URL(fileURLWithPath: "/tmp/\(name)")))
    }

    @Test func offersImageActionsOnlyWhenEveryFileIsAnImage() {
        let image = URL(fileURLWithPath: "/tmp/a.png")
        let document = URL(fileURLWithPath: "/tmp/a.txt")
        #expect(FileActions.available(for: [image]).contains(.convert(.jpeg)))
        #expect(FileActions.available(for: [image]).contains(.makePDF))
        #expect(FileActions.available(for: [image, document]) == [])
        #expect(FileActions.available(for: []) == [])
        // Converting to the format a file already has is not offered for a single file.
        #expect(!FileActions.available(for: [image]).contains(.convert(.png)))
    }
}

@Suite struct ImageProcessorTests {
    @Test func convertsBetweenFormatsKeepingTheSize() throws {
        try withDirectory { directory in
            let source = try makePNG(directory.appendingPathComponent("ảnh.png"))
            let jpeg = try #require(try FileActions.run(.convert(.jpeg), on: source))
            #expect(jpeg.lastPathComponent == "ảnh.jpg")
            #expect(typeIdentifier(of: jpeg) == "public.jpeg")
            #expect(ImageProcessor.pixelSize(of: jpeg)?.width == 120)
            #expect(ImageProcessor.pixelSize(of: jpeg)?.height == 80)

            let heic = try #require(try FileActions.run(.convert(.heic), on: source))
            #expect(typeIdentifier(of: heic) == "public.heic")
            let back = try #require(try FileActions.run(.convert(.png), on: jpeg))
            // "ảnh.png" is the source, so the copy gets a number.
            #expect(back.lastPathComponent == "ảnh 2.png")
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test func resizesToAPercentageOfTheOriginal() throws {
        try withDirectory { directory in
            let source = try makePNG(directory.appendingPathComponent("a.png"), width: 121, height: 80)
            let half = try #require(try FileActions.run(.resize(percent: 50), on: source))
            #expect(half.lastPathComponent == "a-50.png")
            #expect(typeIdentifier(of: half) == "public.png")
            #expect(ImageProcessor.pixelSize(of: half)?.width == 61)
            #expect(ImageProcessor.pixelSize(of: half)?.height == 40)
            let quarter = try #require(try FileActions.run(.resize(percent: 25), on: source))
            #expect(ImageProcessor.pixelSize(of: quarter)?.width == 30)
        }
    }

    @Test func compressingAPhotoWritesASmallerJPEGOfTheSameSize() throws {
        try withDirectory { directory in
            let source = try makePNG(directory.appendingPathComponent("a.png"), width: 400, height: 300, photoLike: true)
            let compressed = try #require(try FileActions.run(.compress, on: source))
            #expect(compressed.lastPathComponent == "a-compressed.jpg")
            #expect(typeIdentifier(of: compressed) == "public.jpeg")
            #expect(ImageProcessor.pixelSize(of: compressed)?.width == 400)
            #expect(try fileSize(compressed) < fileSize(source))
        }
    }

    @Test func compressingAPictureWithTransparencyKeepsIt() throws {
        try withDirectory { directory in
            let source = try makePNG(
                directory.appendingPathComponent("a.png"), width: 400, height: 300, transparent: true, photoLike: true)
            let compressed = try #require(try FileActions.run(.compress, on: source))
            #expect(hasAlpha(compressed))
            #expect(try fileSize(compressed) < fileSize(source))
        }
    }

    @Test func compressingWhatWouldNotGetSmallerLeavesItAlone() throws {
        try withDirectory { directory in
            // A flat picture: PNG is already smaller than any JPEG of it.
            let source = try makePNG(directory.appendingPathComponent("a.png"), width: 400, height: 300)
            #expect(try FileActions.run(.compress, on: source) == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["a.png"])
        }
    }

    @Test func convertingToTheFormatAFileAlreadyHasMakesNoCopy() throws {
        try withDirectory { directory in
            let source = try makePNG(directory.appendingPathComponent("a.png"))
            #expect(try FileActions.run(.convert(.png), on: source) == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["a.png"])
        }
    }

    @Test func combinesImagesIntoOnePDFWithAPageEach() throws {
        try withDirectory { directory in
            let first = try makePNG(directory.appendingPathComponent("a.png"), width: 200, height: 100)
            let second = try makePNG(directory.appendingPathComponent("b.png"), width: 50, height: 300)
            let pdf = try FileActions.makePDF(from: [first, second])
            #expect(pdf.lastPathComponent == "a.pdf")
            let document = try #require(CGPDFDocument(pdf as CFURL))
            #expect(document.numberOfPages == 2)
            #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 200, height: 100))
            #expect(document.page(at: 2)?.getBoxRect(.mediaBox).size == CGSize(width: 50, height: 300))
        }
    }

    @Test func aFileThatIsNotAnImageIsRefused() throws {
        try withDirectory { directory in
            let text = directory.appendingPathComponent("a.png")
            try Data("không phải ảnh".utf8).write(to: text)
            #expect(throws: FileActionError.notAnImage) { try FileActions.run(.convert(.jpeg), on: text) }
            #expect(throws: FileActionError.notAnImage) { try FileActions.makePDF(from: [text]) }
            #expect(throws: FileActionError.nothingToDo) { try FileActions.makePDF(from: []) }
            // Nothing half-written is left behind.
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["a.png"])
        }
    }
}
