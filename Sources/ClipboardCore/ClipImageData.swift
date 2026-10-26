import CoreGraphics
import Foundation
import ImageIO

/// How a copied picture is kept. A screenshot stays PNG, exact to the pixel; a large photo,
/// which PNG keeps at many megabytes, is kept as HEIC, a fraction of the size with no visible
/// loss. A picture with see-through parts stays PNG whatever its size.
public enum ClipImageData {
    /// Above this a PNG is worth making smaller.
    public static let largePNGBytes = 4_000_000
    /// HEIC is kept only when it saves at least this share of the PNG.
    static let worthwhileShare = 0.7
    static let heicQuality = 0.85

    /// The data to store for picture data as it came off the pasteboard (PNG, TIFF or any
    /// format Image I/O reads). Nil when it is not a picture. Slow for a large picture: call it
    /// away from the main thread.
    public static func stored(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let isPNG = CGImageSourceGetType(source) as String? == "public.png"
        if isPNG, data.count <= largePNGBytes {
            return data
        }
        guard let png = isPNG ? data : encode(image, as: "public.png", quality: nil) else { return nil }
        guard png.count > largePNGBytes, !isTransparent(image),
              let heic = encode(image, as: "public.heic", quality: heicQuality),
              Double(heic.count) < Double(png.count) * worthwhileShare
        else { return png }
        return heic
    }

    /// The type identifier of stored picture data, e.g. `public.png`.
    public static func typeIdentifier(of data: Data) -> String? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(CGImageSourceGetType) as String?
    }

    /// The file extension a stored picture is saved under.
    public static func fileExtension(of data: Data) -> String {
        typeIdentifier(of: data) == "public.heic" ? "heic" : "png"
    }

    static func encode(_ image: CGImage, as type: String, quality: Double?) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type as CFString, 1, nil) else { return nil }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// Whether any pixel is see-through. Many opaque pictures carry an alpha channel all the same.
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
}
