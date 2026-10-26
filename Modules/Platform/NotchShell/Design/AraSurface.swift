import AppKit
import SwiftUI

/// Measures and motion shared by every surface of the app.
public enum AraTheme {
    public static let cardRadius: CGFloat = 16
    public static let rowRadius: CGFloat = 12
    /// The weight of the thin outline of a field or an outlined button.
    public static let outline: CGFloat = 1.5
    /// How a control answers a press: fast in, a little bounce out.
    public static let press = Animation.spring(response: 0.22, dampingFraction: 0.62)
    /// How a control answers the pointer arriving or leaving.
    public static let hover = Animation.easeOut(duration: 0.14)
    /// How content settles when something changes place or size.
    public static let settle = Animation.spring(response: 0.34, dampingFraction: 0.8)

    public static let secondaryText = AraPalette.ink.opacity(0.68)
    public static let tertiaryText = AraPalette.ink.opacity(0.5)

    /// Marks drawn on a filled control.
    public static let onAccent = AraPalette.onAccent
}

/// How much a surface stands out from what is under it.
public enum AraSurfaceLevel: Sendable {
    /// A resting card or row.
    case plate
    /// A well: a quiet button, a bar of tools, a card under the pointer.
    case raised
    /// The chosen one of several: drawn as the other palette's card, black among white by
    /// day and light among dark at night.
    case selected
}

/// A flat surface with no outline: the white card of the design, a beige well in it, or one
/// of the theme's other colours.
struct AraSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.araScale) private var ui
    let shape: S
    let level: AraSurfaceLevel
    /// Fills the surface with one of the theme's other colours instead of the card's own.
    var hue: AraHue?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.araHue) private var surroundingHue

    /// The palette the surface and what is on it are drawn with.
    private var scheme: ColorScheme {
        switch level {
        case .plate, .raised: colorScheme
        case .selected: colorScheme == .dark ? .light : .dark
        }
    }

    func body(content: Content) -> some View {
        let tint = hue.map(AraPalette.tint)
        content
            .foregroundStyle(tint?.ink ?? AraPalette.ink)
            // What is on a coloured card takes that colour; elsewhere the page's carries on.
            .environment(\.araHue, hue ?? surroundingHue)
            .environment(\.colorScheme, scheme)
            .background {
                shape.fill(tint?.fill ?? (level == .raised ? AraPalette.well : AraPalette.card))
                    .environment(\.colorScheme, scheme)
                    .allowsHitTesting(false)
            }
    }
}

public extension View {
    /// Draws the view in a well of the given shape: a bar of tools, a quiet field.
    func araSurface<S: InsettableShape>(_ shape: S, level: AraSurfaceLevel = .raised) -> some View {
        modifier(AraSurfaceModifier(shape: shape, level: level))
    }

    /// A card with the app's corner radius. The radius is in the layout's points and grows
    /// with the notch.
    func araCard(radius: CGFloat = AraTheme.cardRadius, level: AraSurfaceLevel = .plate, hue: AraHue? = nil) -> some View {
        modifier(AraRoundedSurface(radius: radius, level: level, hue: hue))
    }

    /// A field to type in: a pill with the design's thin outline.
    func araField() -> some View {
        modifier(AraFieldModifier())
    }

    /// Marks the chosen one of several cards that each have a colour of their own: a ring
    /// a little way outside the card, so it shows whatever the card's colour.
    func araSelectionRing(_ isSelected: Bool, radius: CGFloat = AraTheme.cardRadius) -> some View {
        modifier(AraSelectionRingModifier(isSelected: isSelected, radius: radius))
    }

    /// A row of a list on a card: drawn as the other palette's card when it is the chosen one.
    @ViewBuilder
    func araRow(isSelected: Bool, radius: CGFloat = 10) -> some View {
        if isSelected {
            modifier(AraRoundedSurface(radius: radius, level: .selected, hue: nil))
        } else {
            self
        }
    }
}

/// A surface with rounded corners whose radius grows with the notch.
struct AraRoundedSurface: ViewModifier {
    @Environment(\.araScale) private var ui
    let radius: CGFloat
    let level: AraSurfaceLevel
    let hue: AraHue?

    func body(content: Content) -> some View {
        content.modifier(AraSurfaceModifier(
            shape: RoundedRectangle(cornerRadius: radius * ui, style: .continuous), level: level, hue: hue))
    }
}

struct AraFieldModifier: ViewModifier {
    @Environment(\.araScale) private var ui

    func body(content: Content) -> some View {
        content
            .foregroundStyle(AraPalette.ink)
            .background {
                Capsule().fill(AraPalette.card)
                    .overlay { Capsule().strokeBorder(AraPalette.line, lineWidth: AraTheme.outline * ui) }
                    .allowsHitTesting(false)
            }
    }
}

struct AraSelectionRingModifier: ViewModifier {
    @Environment(\.araScale) private var ui
    let isSelected: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: (radius + 3.5) * ui, style: .continuous)
                .strokeBorder(AraPalette.onGround, lineWidth: 2 * ui)
                .padding(-3.5 * ui)
                .opacity(isSelected ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// What the open notch is laid on: the theme's ground, reaching up to the black of the
/// hardware notch without a seam.
public struct AraNotchGround: View {
    @Environment(\.araScale) private var ui
    public init() {}

    public var body: some View {
        AraPalette.ground
            .mask(LinearGradient(
                stops: [.init(color: .clear, location: 0.08), .init(color: .black, location: 0.3)],
                startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

/// A thin line that fills from the leading edge.
public struct AraProgressLine: View {
    @Environment(\.araScale) private var ui
    let fraction: Double
    var height: CGFloat
    @Environment(\.araHue) private var hue

    public init(fraction: Double, height: CGFloat = 4) {
        self.fraction = fraction
        self.height = height
    }

    public var body: some View {
        let height = height * ui
        return GeometryReader { area in
            ZStack(alignment: .leading) {
                Capsule().fill(AraPalette.track)
                Capsule().fill(hue.map { AraPalette.tint($0).line } ?? AraPalette.ink)
                    .frame(width: max(height, area.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// A small ring that fills clockwise from the top: progress where there is no room for a line.
public struct AraProgressRing: View {
    @Environment(\.araScale) private var ui
    let fraction: Double
    var lineWidth: CGFloat

    public init(fraction: Double, lineWidth: CGFloat = 2.2) {
        self.fraction = fraction
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let lineWidth = lineWidth * ui
        return ZStack {
            Circle().stroke(AraPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0.02), 1))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
}

/// What a page shows when it has nothing: one icon in a well, a title in the display face,
/// and at most one more line.
public struct AraEmptyState: View {
    @Environment(\.araScale) private var ui
    let icon: AraIcon
    let title: String
    var detail: String?
    @Environment(\.araHue) private var hue

    public init(icon: AraIcon, title: String, detail: String? = nil) {
        self.icon = icon
        self.title = title
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: 7 * ui) {
            icon.image
                .font(.system(size: 17 * ui, weight: .medium))
                .foregroundStyle(AraPalette.label(in: hue))
                .frame(width: 42 * ui, height: 42 * ui)
                .background(AraPalette.well, in: Circle())
            Text(title)
                .font(AraType.display(15 * ui))
            if let detail {
                // Dimmed, not coloured: the state may be on a card or straight on the ground.
                Text(detail)
                    .font(.system(size: 11 * ui))
                    .opacity(0.68)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

public extension View {
    /// Fades the last few points of a list that scrolls up and down, so a row cut off by the
    /// edge reads as "there is more" and not as a drawing mistake.
    func araScrollFade(length: CGFloat = 14) -> some View {
        modifier(AraScrollFadeModifier(length: length))
    }
}

struct AraScrollFadeModifier: ViewModifier {
    @Environment(\.araScale) private var ui
    let length: CGFloat

    func body(content: Content) -> some View {
        content.mask {
            VStack(spacing: 0 * ui) {
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: length * ui)
            }
        }
    }
}

/// The sizes text comes in. Four steps for reading, and large numerals chosen case by case
/// for the few things read from across the room: a countdown, a title.
public enum AraType {
    public static let caption: CGFloat = 10
    public static let footnote: CGFloat = 11
    public static let body: CGFloat = 12
    public static let title: CGFloat = 14

    /// The display face, for names and headings: the system's serif.
    public static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
