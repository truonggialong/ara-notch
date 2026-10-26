import CoreGraphics
import Foundation
import ImageIO

/// The image formats files can be converted to.
public enum ImageFormat: String, CaseIterable, Sendable {
    case png
    case jpeg
    case heic

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    var typeIdentifier: String {
        "public.\(rawValue)"
    }

    /// The format a file has, going by its extension.
    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        case "heic", "heif": self = .heic
        default: return nil
        }
    }
}

/// What can be done with files dropped on the notch.
public enum FileAction: Hashable, Sendable {
    case convert(ImageFormat)
    /// A copy scaled to this percentage of the width and height.
    case resize(percent: Int)
    /// A smaller copy at reduced quality: JPEG, or HEIC when the picture has transparency.
    case compress
    /// One PDF with a page per image.
    case makePDF
}

public enum FileActionError: Error, Equatable {
    case notAnImage
    case cannotWrite
    case nothingToDo
}

/// Chooses where a result goes: next to its source, under a name nothing else has.
public enum OutputNaming {
    /// - Parameters:
    ///   - suffix: added to the source's name, e.g. `-50`.
    ///   - folder: where to put the result; defaults to the source's folder.
    ///   - exists: whether a file is already at a URL.
    public static func destination(
        for source: URL, suffix: String, fileExtension: String, in folder: URL? = nil, exists: (URL) -> Bool
    ) -> URL {
        let folder = folder ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = folder.appendingPathComponent("\(base).\(fileExtension)")
        var number = 2
        while exists(candidate) {
            candidate = folder.appendingPathComponent("\(base) \(number).\(fileExtension)")
            number += 1
        }
        return candidate
    }
}

/// Reads and writes image files through Image I/O.
public enum ImageProcessor {
    static let convertQuality = 0.9
    static let compressQuality = 0.5

    /// Width and height in pixels, as displayed (a rotated photo reports its upright size).
    public static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? (height, width) : (width, height)
    }

    /// Whether any part of the picture is see-through. Many opaque pictures carry an alpha
    /// channel all the same, so the pixels themselves are looked at.
    static func isTransparent(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        let width = image.width, height = image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let data = context.data
        else { return true }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = data.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
        for row in 0..<height {
            let line = bytes + row * context.bytesPerRow
            for column in 0..<width where line[column * 4 + 3] < 255 {
                return true
            }
        }
        return false
    }

    /// The image upright, at full size.
    static func image(at url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0,
              let size = pixelSize(of: url)
        else { throw FileActionError.notAnImage }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw FileActionError.notAnImage
        }
        return image
    }

    static func scaled(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil, width: max(1, width), height: max(1, height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw FileActionError.cannotWrite }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: max(1, width), height: max(1, height)))
        guard let result = context.makeImage() else { throw FileActionError.cannotWrite }
        return result
    }

    /// Writes the image in a format. The file appears under its final name only when complete.
    static func write(_ image: CGImage, as format: ImageFormat, quality: Double, to destination: URL) throws {
        let partial = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: partial) }
        guard let writer = CGImageDestinationCreateWithURL(
            partial as CFURL, format.typeIdentifier as CFString, 1, nil)
        else { throw FileActionError.cannotWrite }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            // JPEG has no transparency; see-through areas become white rather than black.
            kCGImageDestinationBackgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        ]
        CGImageDestinationAddImage(writer, image, options as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw FileActionError.cannotWrite }
        do {
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            throw FileActionError.cannotWrite
        }
    }
}

/// Runs the actions offered for dropped files. Results are new files; sources are never changed.
public enum FileActions {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
    ]

    public static func isImage(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// The actions that make sense for these files, in menu order. Image actions need every
    /// file to be an image.
    public static func available(for urls: [URL]) -> [FileAction] {
        guard !urls.isEmpty, urls.allSatisfy(isImage) else { return [] }
        let onlyFormat = urls.count == 1 ? ImageFormat(fileExtension: urls[0].pathExtension) : nil
        let conversions = ImageFormat.allCases.filter { $0 != onlyFormat }.map(FileAction.convert)
        return conversions + [.resize(percent: 50), .resize(percent: 25), .compress, .makePDF]
    }

    /// Applies an action to one image and returns the new file. `.makePDF` makes a one-page PDF.
    /// Nil when there was nothing to make: the file already has that format, or compressing it
    /// would not make it smaller.
    @discardableResult
    public static func run(_ action: FileAction, on source: URL) throws -> URL? {
        if case .makePDF = action {
            return try makePDF(from: [source])
        }
        let image = try ImageProcessor.image(at: source)
        let sourceFormat = ImageFormat(fileExtension: source.pathExtension)

        switch action {
        case .convert(let format):
            guard format != sourceFormat else { return nil }
            let destination = destination(for: source, suffix: "", fileExtension: format.fileExtension)
            try ImageProcessor.write(image, as: format, quality: ImageProcessor.convertQuality, to: destination)
            return destination
        case .resize(let percent):
            let factor = Double(max(1, percent)) / 100
            let resized = try ImageProcessor.scaled(
                image,
                width: Int((Double(image.width) * factor).rounded()),
                height: Int((Double(image.height) * factor).rounded()))
            // A format that cannot be written (GIF, WebP, …) is saved as PNG.
            let format = sourceFormat ?? .png
            let destination = destination(for: source, suffix: "-\(percent)", fileExtension: format.fileExtension)
            try ImageProcessor.write(resized, as: format, quality: ImageProcessor.convertQuality, to: destination)
            return destination
        case .compress:
            // JPEG has no transparency; HEIC keeps it.
            let format: ImageFormat = ImageProcessor.isTransparent(image) ? .heic : .jpeg
            let destination = destination(for: source, suffix: "-compressed", fileExtension: format.fileExtension)
            try ImageProcessor.write(image, as: format, quality: ImageProcessor.compressQuality, to: destination)
            // A flat picture is often smaller as it is; a larger "compressed" copy helps no one.
            let size = { (url: URL) in (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
            guard size(destination) < size(source) else {
                try? FileManager.default.removeItem(at: destination)
                return nil
            }
            return destination
        case .makePDF:
            throw FileActionError.nothingToDo
        }
    }

    /// One PDF with a page per image, each page the size of its image; named after the first.
    @discardableResult
    public static func makePDF(from sources: [URL]) throws -> URL {
        guard let first = sources.first else { throw FileActionError.nothingToDo }
        // Read everything before writing anything, so a bad file leaves nothing behind.
        let images = try sources.map(ImageProcessor.image(at:))
        let destination = destination(for: first, suffix: "", fileExtension: "pdf")
        let partial = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: partial) }

        guard let context = CGContext(partial as CFURL, mediaBox: nil, nil) else { throw FileActionError.cannotWrite }
        for image in images {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            context.endPage()
        }
        context.closePDF()
        do {
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            throw FileActionError.cannotWrite
        }
        return destination
    }

    /// Next to the source when that folder can be written to, otherwise in Downloads.
    private static func destination(for source: URL, suffix: String, fileExtension: String) -> URL {
        let manager = FileManager.default
        let folder = source.deletingLastPathComponent()
        let target = manager.isWritableFile(atPath: folder.path)
            ? folder
            : manager.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? folder
        return OutputNaming.destination(for: source, suffix: suffix, fileExtension: fileExtension, in: target) {
            manager.fileExists(atPath: $0.path)
        }
    }
}
