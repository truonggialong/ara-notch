import AppKit
import NotchCore
import SwiftUI

/// One of the colours mixed in beside the black, the white and the orange: each page of the
/// notch has one, and so has each kind of clip.
public typealias AraHue = ThemeHue

/// A hue as it is drawn: the fill of a card in that colour, the fresh colour of its
/// captions and filled controls, and the text on it. A control filled with `line` carries marks in `fill`.
public struct AraTint: Sendable {
    public let fill: Color
    public let line: Color
    public let ink: Color
}

private struct AraHueKey: EnvironmentKey {
    static let defaultValue: AraHue? = nil
}

public extension EnvironmentValues {
    /// The colour of the page or card a view is in; nil where there is none.
    var araHue: AraHue? {
        get { self[AraHueKey.self] }
        set { self[AraHueKey.self] = newValue }
    }
}

public extension View {
    /// Gives everything inside the colour of a page: its labels and its filled controls.
    func araHue(_ hue: AraHue?) -> some View {
        environment(\.araHue, hue)
    }
}

/// The theme's colours, ready to draw with. Each follows the appearance of the view it is
/// used in: the day sheet or the night one.
public enum AraPalette {
    public static let ground = color(\.ground)
    public static let onGround = color(\.onGround)
    public static let card = color(\.card)
    public static let cardRaised = color(\.cardRaised)
    public static let ink = color(\.ink)
    public static let label = color(\.label)
    public static let value = color(\.value)
    public static let accent = color(\.accent)
    public static let onAccent = color(\.onAccent)
    public static let danger = color(\.danger)
    public static let onDanger = color(\.onDanger)
    public static let warning = color(\.warning)
    public static let line = color(\.line)

    /// A hue, in the light of the view it is used in.
    public static func tint(_ hue: AraHue) -> AraTint {
        tints[hue] ?? AraTint(fill: card, line: line, ink: ink)
    }

    private static let tints: [AraHue: AraTint] = Dictionary(uniqueKeysWithValues: AraHue.allCases.map { hue in
        func part(_ part: KeyPath<ThemeTint, ThemeColor>) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return fixed((isDark ? ThemePalette.night : ThemePalette.paper).tint(hue)[keyPath: part])
            })
        }
        return (hue, AraTint(fill: part(\.fill), line: part(\.line), ink: part(\.ink)))
    })

    /// The colour of small labels where the page or card has a colour of its own.
    public static func label(in hue: AraHue?) -> Color {
        hue.map { tint($0).line } ?? label
    }

    /// The fill of the one control a view is about, and the marks on it, in the page's colour.
    public static func accent(in hue: AraHue?) -> Color {
        hue.map { tint($0).line } ?? accent
    }

    public static func onAccent(in hue: AraHue?) -> Color {
        hue.map { tint($0).fill } ?? onAccent
    }

    /// A well in a card or on the ground: a quiet button, a field, a bar of tools.
    public static let well = cardRaised
    /// The one orange and the marks on it.
    public static let brand = color(\.brand)
    public static let onBrand = color(\.onBrand)
    /// A divider, the empty part of a progress line, and the wash under the pointer.
    public static let hairline = ink.opacity(0.12)
    public static let track = ink.opacity(0.16)
    public static let hoverWash = ink.opacity(0.08)
    /// Plain white, for paper a file's picture lies on, day and night.
    public static let sheet = Color.white

    /// The overview's widgets: dark cards in every appearance, the feature's colour made
    /// brighter, and the alert orange (`WidgetPalette`).
    public static func vivid(_ hue: AraHue?) -> Color {
        Color(nsColor: fixed(hue.map(WidgetPalette.vivid) ?? WidgetPalette.text))
    }

    public static let alert = Color(nsColor: fixed(WidgetPalette.alert))
    public static let widgetCard = Color(nsColor: fixed(WidgetPalette.card))
    public static let widgetText = Color(nsColor: fixed(WidgetPalette.text))
    public static let widgetSecondary = Color(nsColor: fixed(WidgetPalette.secondaryText))
    public static let widgetTrack = Color(nsColor: fixed(WidgetPalette.track))
    public static let widgetQuiet = Color(nsColor: fixed(WidgetPalette.quietButton))

    /// The same colours for AppKit, which windows and text views are painted with.
    public static func nsColor(_ part: KeyPath<ThemePalette, ThemeColor>) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return fixed((isDark ? ThemePalette.night : ThemePalette.paper)[keyPath: part])
        }
    }

    /// Text on a card, the ground of a window, and a card, for AppKit.
    public static let nsInk = nsColor(\.ink)
    public static let nsGround = nsColor(\.ground)
    public static let nsCard = nsColor(\.card)

    /// Text on a card that has not been typed yet: the ink, faint.
    public static let nsPlaceholder = NSColor(name: nil) { appearance in
        nsInk.resolved(for: appearance).withAlphaComponent(0.45)
    }

    /// The system's rounded face, for AppKit views.
    public static func nsFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let plain = NSFont.systemFont(ofSize: size, weight: weight)
        return plain.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? plain
    }

    private static func color(_ part: KeyPath<ThemePalette, ThemeColor>) -> Color {
        Color(nsColor: nsColor(part))
    }

    private static func fixed(_ color: ThemeColor) -> NSColor {
        NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}

private extension NSColor {
    /// The colour as it is under the given appearance.
    func resolved(for appearance: NSAppearance) -> NSColor {
        var result = self
        appearance.performAsCurrentDrawingAppearance {
            result = self.usingColorSpace(.sRGB) ?? self
        }
        return result
    }
}
