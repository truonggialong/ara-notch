import Foundation

/// The two colours a playing track is drawn in beside the closed notch, taken from its
/// artwork: the artwork's strongest colour and a second one, both bright enough to read on
/// black. The bars and the progress line run from the first to the second.
public struct TrackColors: Equatable, Sendable {
    /// A colour as red, green and blue in 0…1.
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// 0..<360.
        public var hue: Double { HSV(self).hue }
        public var brightness: Double { HSV(self).value }
    }

    public var first: RGB
    public var second: RGB

    /// How far round the colour wheel the second colour is turned when the artwork has only one.
    static let neighbourTurn: Double = 40
    /// No colour is darker than this, so it still shows on the black notch.
    static let leastBrightness = 0.88
    /// A pixel paler or darker than these carries no colour worth taking.
    private static let leastSaturation = 0.25
    private static let leastValue = 0.2
    /// Of the colour found, how much the artwork must have before a hue counts as its second
    /// colour, and how much before it has any colour at all.
    private static let secondShare = 0.2
    private static let colourfulShare = 0.03
    private static let bucketCount = 12

    /// From the artwork's pixels; nil when it has no colour worth taking (grey, black or
    /// white artwork).
    public static func from(pixels: [RGB]) -> TrackColors? {
        guard !pixels.isEmpty else { return nil }
        var weights = [Double](repeating: 0, count: bucketCount)
        var sums = [RGB](repeating: RGB(red: 0, green: 0, blue: 0), count: bucketCount)
        for pixel in pixels {
            let hsv = HSV(pixel)
            guard hsv.saturation >= leastSaturation, hsv.value >= leastValue else { continue }
            // Vivid, bright pixels say more about the artwork's colour than dull ones.
            let weight = hsv.saturation * hsv.value
            let bucket = Int(hsv.hue / 360 * Double(bucketCount)) % bucketCount
            weights[bucket] += weight
            sums[bucket].red += pixel.red * weight
            sums[bucket].green += pixel.green * weight
            sums[bucket].blue += pixel.blue * weight
        }
        guard weights.reduce(0, +) >= colourfulShare * Double(pixels.count),
              let best = weights.indices.max(by: { weights[$0] < weights[$1] })
        else { return nil }
        let first = average(sums[best], weight: weights[best])
        // A second hue counts only when it is well apart from the first and not a small spot.
        let apart = weights.indices.filter { bucket in
            let distance = abs(bucket - best)
            return min(distance, bucketCount - distance) >= 2 && weights[bucket] >= secondShare * weights[best]
        }
        let second = apart.max(by: { weights[$0] < weights[$1] }).map { average(sums[$0], weight: weights[$0]) }
            ?? HSV(first).turned(by: neighbourTurn).rgb
        return TrackColors(first: readable(first), second: readable(second))
    }

    private static func average(_ sum: RGB, weight: Double) -> RGB {
        RGB(red: sum.red / weight, green: sum.green / weight, blue: sum.blue / weight)
    }

    /// Bright, and neither washed out nor glaring.
    private static func readable(_ color: RGB) -> RGB {
        var hsv = HSV(color)
        hsv.saturation = min(max(hsv.saturation, 0.45), 0.85)
        hsv.value = max(hsv.value, leastBrightness)
        return hsv.rgb
    }
}

/// Hue in 0..<360, saturation and value in 0…1.
private struct HSV {
    var hue: Double
    var saturation: Double
    var value: Double

    init(_ color: TrackColors.RGB) {
        let high = max(color.red, color.green, color.blue)
        let low = min(color.red, color.green, color.blue)
        let range = high - low
        value = high
        saturation = high > 0 ? range / high : 0
        guard range > 0 else {
            hue = 0
            return
        }
        var hue: Double
        if high == color.red {
            hue = (color.green - color.blue) / range
        } else if high == color.green {
            hue = 2 + (color.blue - color.red) / range
        } else {
            hue = 4 + (color.red - color.green) / range
        }
        hue *= 60
        self.hue = hue < 0 ? hue + 360 : hue
    }

    func turned(by degrees: Double) -> HSV {
        var turned = self
        turned.hue = (hue + degrees).truncatingRemainder(dividingBy: 360)
        return turned
    }

    var rgb: TrackColors.RGB {
        let sector = hue / 60
        let chroma = value * saturation
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) % 6 {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let lift = value - chroma
        return TrackColors.RGB(red: r + lift, green: g + lift, blue: b + lift)
    }
}
