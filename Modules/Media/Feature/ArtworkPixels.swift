import AppKit
import MediaCore

/// A picture's colours, read from a small copy of it.
enum ArtworkPixels {
    /// The pixels of the picture drawn 24 points square; transparent pixels left out.
    static func sample(_ image: NSImage, side: Int = 24) -> [TrackColors.RGB] {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let picture = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        context.interpolationQuality = .medium
        context.draw(picture, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return [] }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var pixels: [TrackColors.RGB] = []
        pixels.reserveCapacity(side * side)
        for index in 0..<(side * side) {
            let alpha = Double(bytes[index * 4 + 3]) / 255
            // An icon's see-through corners carry no colour.
            guard alpha > 0.5 else { continue }
            pixels.append(TrackColors.RGB(
                red: Double(bytes[index * 4]) / 255 / alpha,
                green: Double(bytes[index * 4 + 1]) / 255 / alpha,
                blue: Double(bytes[index * 4 + 2]) / 255 / alpha))
        }
        return pixels
    }
}
