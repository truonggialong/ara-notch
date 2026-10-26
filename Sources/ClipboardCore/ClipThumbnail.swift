import CoreGraphics
import Foundation
import ImageIO

/// The picture a clip is shown with on its card and in the preview: a copy no larger than the
/// preview needs. Decoding the stored picture whole would keep a screenshot of a Retina
/// display at about 24 MB in memory, for a card a few hundred points wide.
public enum ClipThumbnail {
    /// The longest side, in pixels: the large preview at twice the points, with room to spare.
    public static let maxPixelSize = 1024
    /// The longest side for a card, which is a few hundred points wide at most.
    public static let cardPixelSize = 512

    /// A copy no larger than `maxPixelSize` on its longest side, upright; never enlarged.
    /// Nil when the data is no picture.
    public static func image(from data: Data, maxPixelSize: Int = maxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// What the copy takes in memory once drawn, for the cache that holds it.
    public static func cost(of image: CGImage) -> Int {
        image.bytesPerRow * image.height
    }
}
