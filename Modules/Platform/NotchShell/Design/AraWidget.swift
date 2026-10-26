import NotchCore
import SwiftUI

private struct AraTileSizeKey: EnvironmentKey {
    static let defaultValue: WidgetSize = .wide
}

public extension EnvironmentValues {
    /// The size the widget being drawn was given; each feature draws its widget for it.
    var araTileSize: WidgetSize {
        get { self[AraTileSizeKey.self] }
        set { self[AraTileSizeKey.self] = newValue }
    }
}

/// The smallest text a widget has, before enlargement.
let araWidgetSmallestText: CGFloat = 10.5

/// One widget of the overview: a dark card on the black notch, one big number, small labels
/// above and below, and the feature's colour on the bars and buttons. A click on the card
/// where there is no button opens the feature's page.
public struct AraWidget<Content: View>: View {
    @Environment(\.araScale) private var ui
    let name: String
    let hue: AraHue?
    let onOpen: (() -> Void)?
    let actionName: String?
    let content: () -> Content
    @StateObject private var hover = AraHover()

    /// `name` says what the widget is, for VoiceOver; `actionName` what a click on the card
    /// does, when that is not opening the feature's page.
    public init(
        name: String, hue: AraHue?, onOpen: (() -> Void)? = nil, actionName: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.name = name
        self.hue = hue
        self.onOpen = onOpen
        self.actionName = actionName
        self.content = content
    }

    public var body: some View {
        let card = RoundedRectangle(cornerRadius: 14 * ui, style: .continuous)
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.vertical, 9 * ui)
            .padding(.horizontal, 11 * ui)
            .foregroundStyle(AraPalette.widgetText)
            .background(card.fill(AraPalette.widgetCard).brightness(onOpen != nil && hover.isHovered ? 0.03 : 0))
            .clipShape(card)
            .contentShape(card)
            // Buttons inside take their own clicks first; the rest of the card opens the page.
            .onTapGesture { onOpen?() }
            .onHover { hover.isHovered = $0 }
            .araHue(hue)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(name)
            .accessibilityActions {
                if let onOpen {
                    Button(actionName ?? L10n.string("widget.open"), action: onOpen)
                }
            }
    }
}

/// A widget's top line: a small label on the left, a status chip on the right.
public struct AraWidgetHeader: View {
    @Environment(\.araScale) private var ui
    let label: String
    let chip: AraStatusChip?

    public init(label: String, chip: AraStatusChip? = nil) {
        self.label = label
        self.chip = chip
    }

    public var body: some View {
        HStack(spacing: 4 * ui) {
            Text(label)
                .font(.system(size: araWidgetSmallestText * ui, weight: .semibold))
                .foregroundStyle(AraPalette.widgetSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            chip
        }
    }
}

/// A small rounded label in the feature's colour on a dim fill of it; orange when it asks for the user.
public struct AraStatusChip: View {
    @Environment(\.araScale) private var ui
    let text: String
    let hue: AraHue?
    let isAlert: Bool

    public init(text: String, hue: AraHue?, isAlert: Bool = false) {
        self.text = text
        self.hue = hue
        self.isAlert = isAlert
    }

    public var body: some View {
        let colour = isAlert ? AraPalette.alert : AraPalette.vivid(hue)
        Text(text)
            .font(.system(size: araWidgetSmallestText * ui, weight: .semibold))
            .foregroundStyle(colour)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6 * ui)
            .padding(.vertical, 1 * ui)
            .background(Capsule().fill(colour.opacity(0.18)))
    }
}

/// The widget's one big number.
public struct AraBigValue: View {
    @Environment(\.araScale) private var ui
    let text: String
    let size: CGFloat
    let isAlert: Bool

    public init(_ text: String, size: CGFloat, isAlert: Bool = false) {
        self.text = text
        self.size = size
        self.isAlert = isAlert
    }

    public var body: some View {
        Text(text)
            .font(.system(size: size * ui, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isAlert ? AraPalette.alert : AraPalette.widgetText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            // As tall as the figures, not the font's whole line, so a small widget has room
            // under it; marks above a letter still draw, past the frame.
            .frame(height: size * 1.08 * ui)
    }
}

/// A bar on the dark track: filled in the feature's colour up to `fraction`, or with several
/// spans (the hours of a day), with an orange mark for "now". Its numbers are written beside
/// it, so VoiceOver skips it.
public struct AraTrackBar: View {
    @Environment(\.araScale) private var ui
    let fraction: Double
    let hue: AraHue?
    let isAlert: Bool
    let spans: [ClosedRange<Double>]
    let marker: Double?
    let thin: Bool

    public init(
        fraction: Double, hue: AraHue?, isAlert: Bool = false, spans: [ClosedRange<Double>] = [],
        marker: Double? = nil, thin: Bool = false
    ) {
        self.fraction = fraction
        self.hue = hue
        self.isAlert = isAlert
        self.spans = spans
        self.marker = marker
        self.thin = thin
    }

    public var body: some View {
        let height = (thin ? 3 : 5) * ui
        let colour = isAlert ? AraPalette.alert : AraPalette.vivid(hue)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(AraPalette.widgetTrack).frame(height: height)
                Capsule().fill(colour).frame(width: width * WidgetMeasure.fraction(fraction), height: height)
                ForEach(Array(spans.enumerated()), id: \.offset) { _, range in
                    // At least 3 points long, so a short event still shows, and kept on the bar.
                    let span = WidgetMeasure.span(range, minimumShare: width > 0 ? 3 * ui / width : 0)
                    Capsule().fill(colour)
                        .frame(width: width * span.length, height: height)
                        .offset(x: width * span.start)
                }
                if let marker {
                    // Taller than the bar, without making the bar take more room.
                    Capsule().fill(AraPalette.alert)
                        .frame(width: 2 * ui, height: height + 6 * ui)
                        .offset(x: width * WidgetMeasure.fraction(marker) - 1 * ui)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// A battery as five segments.
public struct AraSegmentBar: View {
    @Environment(\.araScale) private var ui
    let percent: Int
    let hue: AraHue?
    let isAlert: Bool

    public init(percent: Int, hue: AraHue?, isAlert: Bool = false) {
        self.percent = percent
        self.hue = hue
        self.isAlert = isAlert
    }

    public var body: some View {
        let lit = WidgetMeasure.segments(percent: percent, of: 5)
        let colour = isAlert ? AraPalette.alert : AraPalette.vivid(hue)
        HStack(spacing: 3 * ui) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2 * ui, style: .continuous)
                    .fill(index < lit ? colour : AraPalette.widgetTrack)
            }
        }
        .frame(height: 7 * ui)
        .accessibilityHidden(true)
    }
}

/// A round button: the main one filled with the feature's colour, the others quiet.
public struct AraRoundButton: View {
    @Environment(\.araScale) private var ui
    let icon: AraIcon
    let label: String
    let isPrimary: Bool
    let hue: AraHue?
    let diameter: CGFloat
    let action: () -> Void

    public init(
        icon: AraIcon, label: String, isPrimary: Bool = false, hue: AraHue?, diameter: CGFloat = 26,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.label = label
        self.isPrimary = isPrimary
        self.hue = hue
        self.diameter = diameter
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            icon.image
                .font(.system(size: diameter * 0.42 * ui, weight: .bold))
                .foregroundStyle(isPrimary ? AraPalette.widgetCard : AraPalette.widgetText)
                .frame(width: diameter * ui, height: diameter * ui)
                .background(Circle().fill(isPrimary ? AraPalette.vivid(hue) : AraPalette.widgetQuiet))
                .contentShape(Circle())
        }
        .buttonStyle(AraPressStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Two or three small numbers, each with its label under it.
public struct AraStatRow: View {
    @Environment(\.araScale) private var ui
    let items: [(label: String, value: String)]

    public init(_ items: [(label: String, value: String)]) {
        self.items = items
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12 * ui) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 1 * ui) {
                    Text(item.value)
                        .font(.system(size: 12 * ui, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AraPalette.widgetText)
                    Text(item.label)
                        .font(.system(size: araWidgetSmallestText * ui))
                        .foregroundStyle(AraPalette.widgetSecondary)
                }
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A bar the pointer can drag, drawn like `AraTrackBar`: a widget's volume.
public struct AraWidgetSlider: View {
    @Environment(\.araScale) private var ui
    let value: Double
    let hue: AraHue?
    let label: String
    let onChange: (Double) -> Void

    public init(value: Double, hue: AraHue?, label: String, onChange: @escaping (Double) -> Void) {
        self.value = value
        self.hue = hue
        self.label = label
        self.onChange = onChange
    }

    public var body: some View {
        GeometryReader { area in
            AraTrackBar(fraction: value, hue: hue)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    onChange(area.size.width > 0 ? WidgetMeasure.fraction(drag.location.x / area.size.width) : 0)
                })
        }
        .frame(height: 14 * ui)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((WidgetMeasure.fraction(value) * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(WidgetMeasure.fraction(value + 0.1))
            case .decrement: onChange(WidgetMeasure.fraction(value - 0.1))
            @unknown default: break
            }
        }
    }
}
