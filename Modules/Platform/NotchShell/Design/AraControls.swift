import AppKit
import SwiftUI

/// Whether the pointer is over a control. Held in an object because the build tools here
/// cannot expand `@State`.
@MainActor
public final class AraHover: ObservableObject {
    @Published public var isHovered = false

    public init() {}
}

/// The press of every control in the app: it sinks a little and springs back.
public struct AraPressStyle: ButtonStyle {
    @Environment(\.araScale) private var ui
    var depth: CGFloat

    public init(depth: CGFloat = 0.9) {
        self.depth = depth
    }

    public func makeBody(configuration: Configuration) -> some View {
        PressedLabel(configuration: configuration, depth: depth)
    }

    /// With Reduce Motion on, a press only dims; nothing moves.
    private struct PressedLabel: View {
        @Environment(\.araScale) private var ui
        let configuration: Configuration
        let depth: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? depth : 1)
                .opacity(configuration.isPressed ? 0.75 : 1)
                .animation(AraTheme.press, value: configuration.isPressed)
        }
    }
}

/// How an icon button is dressed.
public enum AraButtonLook: Sendable {
    /// A disc of the well's colour: the usual look.
    case outlined
    /// No disc until the pointer is over it: for rows of tools.
    case bare
    /// Filled: the one action a page is about.
    case accent
    /// A disc that fills with red under the pointer: for removing things.
    case danger
    /// No disc until the pointer is over it, then red: for removing things from a row of tools.
    case bareDanger

    var isDanger: Bool {
        self == .danger || self == .bareDanger
    }
}

public enum AraButtonSize: Sendable {
    case small, regular, large

    var diameter: CGFloat {
        switch self {
        case .small: 22
        case .regular: 28
        case .large: 38
        }
    }

    var glyph: CGFloat {
        switch self {
        case .small: 10.5
        case .regular: 12.5
        case .large: 16
        }
    }
}

/// A round button that is only an icon. Its meaning is in its tooltip and its VoiceOver name;
/// it lights up under the pointer and sinks when pressed.
public struct AraIconButton: View {
    @Environment(\.araScale) private var ui
    let icon: AraIcon
    var look: AraButtonLook
    var size: AraButtonSize
    /// True for a switch that is on: drawn filled.
    var isOn: Bool
    /// Replaces the icon's own name when the button means something more specific here.
    var help: String?
    let action: () -> Void
    @StateObject private var hover = AraHover()

    public init(
        _ icon: AraIcon, look: AraButtonLook = .outlined, size: AraButtonSize = .regular, isOn: Bool = false,
        help: String? = nil, action: @escaping () -> Void
    ) {
        self.icon = icon
        self.look = look
        self.size = size
        self.isOn = isOn
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button {
            AraTooltipCenter.shared.hide()
            action()
        } label: {
            AraIconFace(icon: icon, look: look, size: size, isOn: isOn, isHovered: hover.isHovered)
        }
        .buttonStyle(AraPressStyle())
        .onHover { hover.isHovered = $0 }
        // Its name shows at once; the system's tooltip would make the user wait for it.
        .araTooltip(help ?? icon.label, isHovered: hover.isHovered)
        .accessibilityLabel(help ?? icon.label)
    }
}

/// The drawing of an icon button, for controls that are not plain buttons, such as menus.
public struct AraIconFace: View {
    @Environment(\.araScale) private var ui
    let icon: AraIcon
    var look: AraButtonLook
    var size: AraButtonSize
    var isOn: Bool
    var isHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.araHue) private var hue

    public init(
        icon: AraIcon, look: AraButtonLook = .outlined, size: AraButtonSize = .regular, isOn: Bool = false,
        isHovered: Bool = false
    ) {
        self.icon = icon
        self.look = look
        self.size = size
        self.isOn = isOn
        self.isHovered = isHovered
    }

    public var body: some View {
        icon.image
            .font(.system(size: size.glyph * ui, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: size.diameter * ui, height: size.diameter * ui)
            .background { disc }
            .contentShape(Circle())
            .animation(AraTheme.hover, value: isOn)
    }

    private var isFilled: Bool {
        isOn || look == .accent
    }

    private var foreground: Color {
        if isFilled { return AraPalette.onAccent(in: hue) }
        if look.isDanger, isHovered { return AraPalette.onDanger }
        return AraPalette.ink.opacity(isHovered ? 1 : 0.86)
    }

    @ViewBuilder
    private var disc: some View {
        if isFilled {
            Circle().fill(AraPalette.accent(in: hue))
                .opacity(isHovered ? 0.86 : 1)
        } else if look.isDanger, isHovered {
            Circle().fill(AraPalette.danger)
        } else if look == .bare || look == .bareDanger {
            Circle().fill(isHovered ? AraPalette.hoverWash : .clear)
        } else {
            Circle().fill(AraPalette.well)
                .overlay { Circle().fill(isHovered ? AraPalette.hoverWash : .clear) }
        }
    }
}

/// A button with an icon and a few words, for the rare action an icon alone cannot say.
public struct AraPillButton: View {
    @Environment(\.araScale) private var ui
    let icon: AraIcon?
    let title: String
    var isProminent: Bool
    var isDestructive: Bool
    let action: () -> Void
    @StateObject private var hover = AraHover()
    @Environment(\.araHue) private var hue

    /// - Parameter isDestructive: written in the colour of danger, for what cannot be undone.
    public init(
        _ title: String, icon: AraIcon? = nil, isProminent: Bool = false, isDestructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isProminent = isProminent
        self.isDestructive = isDestructive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5 * ui) {
                icon?.image
                    .font(.system(size: 10 * ui, weight: .semibold))
                Text(title)
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(
                isProminent
                    ? AraPalette.onAccent(in: hue)
                    : (isDestructive ? AraPalette.danger : AraPalette.ink).opacity(hover.isHovered ? 1 : 0.88))
            .padding(.horizontal, 12 * ui)
            .frame(height: 26 * ui)
            .background { plate }
            .contentShape(Capsule())
            .animation(AraTheme.hover, value: hover.isHovered)
        }
        .buttonStyle(AraPressStyle(depth: 0.95))
        .onHover { hover.isHovered = $0 }
    }

    @ViewBuilder
    private var plate: some View {
        if isProminent {
            Capsule().fill(AraPalette.accent(in: hue))
                .opacity(hover.isHovered ? 0.86 : 1)
        } else {
            Capsule().fill(AraPalette.well)
                .overlay { Capsule().fill(hover.isHovered ? AraPalette.hoverWash : .clear) }
        }
    }
}

/// One choice among a few, such as a preset: a quiet pill, filled with the page's colour when chosen.
public struct AraChip<Label: View>: View {
    @Environment(\.araScale) private var ui
    var isSelected: Bool
    let action: () -> Void
    let label: () -> Label
    @StateObject private var hover = AraHover()
    @Environment(\.araHue) private var hue

    public init(isSelected: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.isSelected = isSelected
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(
                    isSelected
                        ? (hue.map { AraPalette.tint($0).fill } ?? AraPalette.onBrand)
                        : AraPalette.ink.opacity(hover.isHovered ? 1 : 0.86))
                .padding(.horizontal, 10 * ui)
                .frame(height: 24 * ui)
                .background {
                    // Where the page has no colour of its own, the chosen tag is the one orange.
                    Capsule().fill(isSelected ? (hue.map { AraPalette.tint($0).line } ?? AraPalette.brand) : AraPalette.well)
                        .overlay { Capsule().fill(hover.isHovered && !isSelected ? AraPalette.hoverWash : .clear) }
                }
                .contentShape(Capsule())
                .animation(AraTheme.hover, value: hover.isHovered)
                .animation(AraTheme.hover, value: isSelected)
        }
        .buttonStyle(AraPressStyle(depth: 0.94))
        .onHover { hover.isHovered = $0 }
    }
}

/// Lifts whatever it wraps a little while the pointer is over it: cards and rows that can be
/// clicked say so before the click.
public struct AraHoverLift<Content: View>: View {
    @Environment(\.araScale) private var ui
    var scale: CGFloat
    /// What a drag of the content carries, when it can be dragged. The drag is started here
    /// because the pointer leaving during a drag is never reported: without this the card
    /// would stay lifted after it was dropped somewhere else.
    var dragProvider: (() -> NSItemProvider)?
    let content: (_ isHovered: Bool) -> Content
    @StateObject private var hover = AraHover()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        scale: CGFloat = 1.03, dragProvider: (() -> NSItemProvider)? = nil,
        @ViewBuilder content: @escaping (_ isHovered: Bool) -> Content
    ) {
        self.scale = scale
        self.dragProvider = dragProvider
        self.content = content
    }

    public var body: some View {
        let lifted = content(hover.isHovered)
            .scaleEffect(hover.isHovered && !reduceMotion ? scale : 1)
            // Content that does not lift changes at once: an animation would have the page
            // drawn again on every frame while the pointer travels across a row of them.
            .animation(scale == 1 ? nil : AraTheme.hover, value: hover.isHovered)
            .onHover { hover.isHovered = $0 }
        if let dragProvider {
            lifted.onDrag {
                hover.isHovered = false
                return dragProvider()
            }
        } else {
            lifted
        }
    }
}

/// The explanation under a setting. One line until it is clicked, so a page of settings can
/// be read at a glance; the whole text is also the tooltip.
public struct AraSettingsNote: View {
    @Environment(\.araScale) private var ui
    let text: String
    @StateObject private var expansion = AraHover()

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10 * ui))
            .foregroundStyle(AraTheme.secondaryText)
            .lineLimit(expansion.isHovered ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
            .onTapGesture { expansion.isHovered.toggle() }
            .help(text)
            .animation(AraTheme.hover, value: expansion.isHovered)
    }
}

/// A thin line with a value that can be dragged: thicker under the pointer, with a knob.
public struct AraSlider: View {
    @Environment(\.araScale) private var ui
    let value: Double
    /// Called as the pointer drags, with the value under it.
    let onChange: (Double) -> Void
    /// Called once when the drag ends.
    var onEnded: ((Double) -> Void)?
    @StateObject private var hover = AraHover()
    @Environment(\.araHue) private var hue

    public init(value: Double, onChange: @escaping (Double) -> Void, onEnded: ((Double) -> Void)? = nil) {
        self.value = value
        self.onChange = onChange
        self.onEnded = onEnded
    }

    public var body: some View {
        GeometryReader { area in
            let fraction = min(max(value, 0), 1)
            let height: CGFloat = (hover.isHovered ? 6 : 4) * ui
            ZStack(alignment: .leading) {
                Capsule().fill(AraPalette.track)
                    .frame(height: height)
                Capsule().fill(hue.map { AraPalette.tint($0).line } ?? AraPalette.ink)
                    .frame(width: max(height, area.size.width * fraction), height: height)
                Circle().fill(AraPalette.ink)
                    .frame(width: 12 * ui, height: 12 * ui)
                    .offset(x: min(max(area.size.width * fraction - 6 * ui, 0), area.size.width - 12 * ui))
                    .opacity(hover.isHovered ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in onChange(Self.fraction(at: drag.location.x, width: area.size.width)) }
                    .onEnded { drag in onEnded?(Self.fraction(at: drag.location.x, width: area.size.width)) })
            .animation(AraTheme.hover, value: hover.isHovered)
        }
        .frame(height: 14 * ui)
        .onHover { hover.isHovered = $0 }
    }

    private static func fraction(at x: CGFloat, width: CGFloat) -> Double {
        width > 0 ? Double(min(max(x / width, 0), 1)) : 0
    }
}
