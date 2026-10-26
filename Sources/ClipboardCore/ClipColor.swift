import Foundation

/// A colour parsed from a CSS-style string. Components are in 0…1.
public struct ClipColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Accepts `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()`, `hsl()` and `hsla()`.
    /// The whole string must be the colour.
    /// - Parameter allowingBareHex: also accept six or eight hex digits without `#`. Three
    ///   digits are never accepted bare; they are too easily a word or a number.
    public static func parse(_ string: String, allowingBareHex: Bool = false) -> ClipColor? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("#") {
            return parseHex(String(trimmed.dropFirst()))
        }
        if allowingBareHex, trimmed.count == 6 || trimmed.count == 8, let color = parseHex(trimmed) {
            return color
        }
        return parseFunction(trimmed)
    }

    private static func parseHex(_ digits: String) -> ClipColor? {
        guard [3, 6, 8].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        // Expand the short form: "abc" → "aabbcc".
        let full = digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : digits
        var components: [Double] = []
        var index = full.startIndex
        while index < full.endIndex {
            let next = full.index(index, offsetBy: 2)
            guard let value = UInt8(full[index..<next], radix: 16) else { return nil }
            components.append(Double(value) / 255)
            index = next
        }
        return ClipColor(
            red: components[0], green: components[1], blue: components[2],
            alpha: components.count == 4 ? components[3] : 1)
    }

    private static func parseFunction(_ string: String) -> ClipColor? {
        guard string.hasSuffix(")"), let open = string.firstIndex(of: "(") else { return nil }
        let name = String(string[..<open])
        let arguments = string[string.index(after: open)..<string.index(before: string.endIndex)]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        let hasAlpha: Bool
        switch name {
        case "rgb", "hsl": hasAlpha = false
        case "rgba", "hsla": hasAlpha = true
        default: return nil
        }
        guard arguments.count == (hasAlpha ? 4 : 3) else { return nil }

        var alpha = 1.0
        if hasAlpha {
            guard let value = Double(arguments[3]), (0...1).contains(value) else { return nil }
            alpha = value
        }

        if name.hasPrefix("rgb") {
            let channels = arguments.prefix(3).compactMap { Double($0) }.filter { (0...255).contains($0) }
            guard channels.count == 3 else { return nil }
            return ClipColor(red: channels[0] / 255, green: channels[1] / 255, blue: channels[2] / 255, alpha: alpha)
        }

        guard let hue = Double(arguments[0]), (0...360).contains(hue),
              let saturation = percent(arguments[1]), let lightness = percent(arguments[2])
        else { return nil }
        return fromHSL(hue: hue, saturation: saturation, lightness: lightness, alpha: alpha)
    }

    /// "50%" → 0.5; nil unless it ends in `%` and lies in 0…100.
    private static func percent(_ string: String) -> Double? {
        guard string.hasSuffix("%"), let value = Double(string.dropLast()), (0...100).contains(value) else {
            return nil
        }
        return value / 100
    }

    private static func fromHSL(hue: Double, saturation: Double, lightness: Double, alpha: Double) -> ClipColor {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue.truncatingRemainder(dividingBy: 360)) / 60
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)
        switch sector {
        case ..<1: base = (chroma, second, 0)
        case ..<2: base = (second, chroma, 0)
        case ..<3: base = (0, chroma, second)
        case ..<4: base = (0, second, chroma)
        case ..<5: base = (second, 0, chroma)
        default: base = (chroma, 0, second)
        }
        let match = lightness - chroma / 2
        return ClipColor(red: base.0 + match, green: base.1 + match, blue: base.2 + match, alpha: alpha)
    }

    // MARK: - Writing

    /// The notations a colour can be copied in.
    public enum Format: String, CaseIterable, Sendable {
        case hex
        case rgb
        case hsl
    }

    /// The colour in CSS notation. A translucent colour uses `#RRGGBBAA`, `rgba()` or `hsla()`.
    public func formatted(as format: Format) -> String {
        let isOpaque = alpha >= 1
        let channels = [red, green, blue].map { Int(($0 * 255).rounded()) }
        // Two decimals at most, without trailing zeros: 0.5, 0.25, 0.
        let alphaText = String(format: "%.2f", alpha)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)

        switch format {
        case .hex:
            let digits = (isOpaque ? channels : channels + [Int((alpha * 255).rounded())])
                .map { String(format: "%02X", $0) }
                .joined()
            return "#\(digits)"
        case .rgb:
            let list = channels.map(String.init).joined(separator: ", ")
            return isOpaque ? "rgb(\(list))" : "rgba(\(list), \(alphaText))"
        case .hsl:
            let (hue, saturation, lightness) = hsl
            let list = "\(Int(hue.rounded()) % 360), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%"
            return isOpaque ? "hsl(\(list))" : "hsla(\(list), \(alphaText))"
        }
    }

    /// Hue in degrees, saturation and lightness in 0…1.
    private var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let lightness = (high + low) / 2
        let delta = high - low
        guard delta > 0 else { return (0, 0, lightness) }

        let saturation = delta / (1 - abs(2 * lightness - 1))
        var sector: Double
        if high == red {
            sector = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        if sector < 0 {
            sector += 6
        }
        return (sector * 60, saturation, lightness)
    }
}
