import Foundation

/// A colour of the theme, as plain numbers, so the palette can be checked without drawing.
public struct ThemeColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// 0xRRGGBB, as colours are written in the design.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// How light the colour looks, from 0 (black) to 1 (white).
    public var luminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The contrast between two colours, from 1 (the same) to 21 (black on white).
    public func contrast(with other: ThemeColor) -> Double {
        let lighter = max(luminance, other.luminance), darker = min(luminance, other.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

/// The colours mixed in beside the black, the white and the one orange, so the app is not
/// all one tone. Each page of the notch has one, and so has each kind of clip.
public enum ThemeHue: String, CaseIterable, Sendable {
    case peach, sky, mint, mustard, sage, lilac
}

/// One of those colours, as it is used: a deep or pale fill for a card, the fresh colour for
/// its outline and labels, and the text written on it. A control filled with `line` carries
/// marks in `fill`.
public struct ThemeTint: Equatable, Sendable {
    public let fill: ThemeColor
    public let line: ThemeColor
    public let ink: ThemeColor

    public init(fill: UInt32, line: UInt32, ink: UInt32) {
        self.fill = ThemeColor(hex: fill)
        self.line = ThemeColor(hex: line)
        self.ink = ThemeColor(hex: ink)
    }
}

/// The few flat colours the whole app is drawn with, after a design-system sheet: an
/// off-white ground, white cards with no outline, black pills, beige wells and one orange.
/// `paper` is that sheet; `night` is the same sheet turned over, light on near-black.
public struct ThemePalette: Equatable, Sendable {
    /// What a window or the open notch is laid on.
    public let ground: ThemeColor
    /// Text written straight on the ground.
    public let onGround: ThemeColor
    /// A card, and a well in it: a field, a quiet button, a row under the pointer.
    public let card: ThemeColor
    public let cardRaised: ThemeColor
    /// Text on a card.
    public let ink: ThemeColor
    /// Quiet text: a caption that names something, and the fact beside it.
    public let label: ThemeColor
    public let value: ThemeColor
    /// The one orange, for the chosen tag and for emphasis, and the marks on it.
    public let brand: ThemeColor
    public let onBrand: ThemeColor
    /// The fill of the one control a view is about, and the marks on it.
    public let accent: ThemeColor
    public let onAccent: ThemeColor
    /// The fill of a control that removes something, and the marks on it.
    public let danger: ThemeColor
    public let onDanger: ThemeColor
    /// Something that wants a look but is not wrong: a wait, a pause.
    public let warning: ThemeColor
    /// The thin outline of a field or an outlined button.
    public let line: ThemeColor
    /// The other colours, each in this palette's light.
    private let tints: [ThemeHue: ThemeTint]

    public func tint(_ hue: ThemeHue) -> ThemeTint {
        tints[hue] ?? ThemeTint(fill: 0, line: 0, ink: 0)
    }

    public static let night = ThemePalette(
        ground: ThemeColor(hex: 0x0E0E0D), onGround: ThemeColor(hex: 0xF4F1EA),
        card: ThemeColor(hex: 0x1F1E1C), cardRaised: ThemeColor(hex: 0x2E2B27),
        ink: ThemeColor(hex: 0xF4F1EA), label: ThemeColor(hex: 0xA8A297), value: ThemeColor(hex: 0xC9C3B8),
        brand: ThemeColor(hex: 0xF2703E), onBrand: ThemeColor(hex: 0x1A1A1A),
        accent: ThemeColor(hex: 0xF4F1EA), onAccent: ThemeColor(hex: 0x141414),
        danger: ThemeColor(hex: 0xF0766A), onDanger: ThemeColor(hex: 0x2A0B0B), warning: ThemeColor(hex: 0xF2B36B),
        line: ThemeColor(hex: 0xF4F1EA),
        // At night: a deep fill, the fresh colour on it.
        tints: [
            .peach: ThemeTint(fill: 0x3D2114, line: 0xF2703E, ink: 0xFBE6D8),
            .sky: ThemeTint(fill: 0x1F3A4D, line: 0x8FB9D6, ink: 0xDCEBF5),
            .mint: ThemeTint(fill: 0x1D3F3B, line: 0x7FCFC0, ink: 0xDDF3EE),
            .mustard: ThemeTint(fill: 0x453A12, line: 0xE8C46A, ink: 0xFAF0CF),
            .sage: ThemeTint(fill: 0x2A3D1C, line: 0xA9C58B, ink: 0xE6F0D8),
            .lilac: ThemeTint(fill: 0x35264A, line: 0xC9A6E0, ink: 0xEFE3F8),
        ])

    public static let paper = ThemePalette(
        ground: ThemeColor(hex: 0xF7F5EF), onGround: ThemeColor(hex: 0x1A1A1A),
        card: ThemeColor(hex: 0xFFFFFF), cardRaised: ThemeColor(hex: 0xEFEAE0),
        ink: ThemeColor(hex: 0x1A1A1A), label: ThemeColor(hex: 0x6B665D), value: ThemeColor(hex: 0x57534B),
        brand: ThemeColor(hex: 0xF2703E), onBrand: ThemeColor(hex: 0x1A1A1A),
        accent: ThemeColor(hex: 0x1A1A1A), onAccent: ThemeColor(hex: 0xFFFFFF),
        danger: ThemeColor(hex: 0xC8372D), onDanger: ThemeColor(hex: 0xFFFFFF), warning: ThemeColor(hex: 0x9A5206),
        line: ThemeColor(hex: 0x1A1A1A),
        // By day: a pale fill, the colour deepened until it reads on white.
        tints: [
            .peach: ThemeTint(fill: 0xFCE5D8, line: 0xB93C0A, ink: 0x5A2410),
            .sky: ThemeTint(fill: 0xD6E6F2, line: 0x2F6388, ink: 0x1F3A4D),
            .mint: ThemeTint(fill: 0xD3ECE6, line: 0x1F6A60, ink: 0x1D3F3B),
            .mustard: ThemeTint(fill: 0xF5E3A8, line: 0x7A5C08, ink: 0x4A3A08),
            .sage: ThemeTint(fill: 0xDDE9C9, line: 0x456724, ink: 0x263A12),
            .lilac: ThemeTint(fill: 0xE8DCF3, line: 0x6F4A92, ink: 0x3A2550),
        ])
}
