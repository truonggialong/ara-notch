import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Turns a stored picture (PNG) into the data of another picture format.
enum ClipImageExport {
    /// - Parameter format: "png", "jpeg" or "heic".
    static func data(from imageData: Data, format: String) -> Data? {
        let type: UTType
        switch format {
        case "png": type = .png
        case "jpeg": type = .jpeg
        case "heic": type = .heic
        default: return nil
        }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        // JPEG and HEIC lose a little; at this quality it does not show.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
