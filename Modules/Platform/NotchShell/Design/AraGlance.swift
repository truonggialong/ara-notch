import AppKit
import NotchCore
import SwiftUI

/// The colour a notice wears, after where it comes from: plain news white, a timer orange, an
/// agent violet, what is done green, keeping awake yellow, a warning red.
public enum AraNoticeColor: Equatable, Sendable {
    case plain, timer, agent, done, awake, warning, sky

    public var color: Color {
        switch self {
        case .plain: AraPalette.ink
        case .timer: Color(red: 1, green: 0.42, blue: 0.10)
        case .agent: Color(red: 0.61, green: 0.48, blue: 1)
        case .done: Color(red: 0.20, green: 0.78, blue: 0.48)
        case .awake: Color(red: 1, green: 0.79, blue: 0.24)
        case .warning: Color(red: 1, green: 0.30, blue: 0.31)
        case .sky: Color(red: 0.31, green: 0.66, blue: 1)
        }
    }
}

/// A notice beside the closed notch that reads at a glance: on the left of the camera what
/// speaks, as a pictogram (`AraPictogram`) or a picture; on the right how much or which, as
/// something seen (a level, a ring, the battery's cells, the colour just copied) or, when only a
/// name says it, a few words. Both sides are as wide as the wider one, so the notch stays centred
/// over the camera. See docs/research/notice-pictograms.html.
public struct AraGlance {
    public enum Icon {
        case pictogram(AraPictogram)
        case image(NSImage)
        /// A system symbol, for what the pictograms have no picture of yet.
        case symbol(String)
    }

    /// A little motion on the pictogram, for news that wants the eye.
    public enum Motion: Equatable, Sendable {
        case none, pulse, shake, spin, drop, blink
    }

    /// What shows right of the camera.
    public enum Value {
        case none
        /// A level, 0…1, as a bar.
        case meter(Double)
        /// A battery's charge as five cells, 0…5 of them lit.
        case cells(Int)
        /// How far along, 0…1, as a ring.
        case ring(Double)
        /// A light: on, or beating.
        case light(beating: Bool)
        /// Done.
        case done
        /// A few words: a name, a number that matters.
        case text(String)
        /// The colour just copied.
        case swatch(Color)
        /// A small picture: an image copied, a site's icon.
        case picture(NSImage)
        /// So many, as dots.
        case count(Int)
        /// A pictogram of its own.
        case pictogram(AraPictogram)
    }

    public var icon: Icon
    public var color: AraNoticeColor
    public var motion: Motion
    /// A few words beside the pictogram, such as a meeting's time.
    public var leading: String?
    public var value: Value
    /// The colour of what is on the right; the notice's own when nil.
    public var valueColor: AraNoticeColor?

    public init(
        _ icon: Icon, color: AraNoticeColor = .plain, motion: Motion = .none, leading: String? = nil, value: Value = .none,
        valueColor: AraNoticeColor? = nil
    ) {
        self.icon = icon
        self.color = color
        self.motion = motion
        self.leading = leading
        self.value = value
        self.valueColor = valueColor
    }

    public init(
        _ pictogram: AraPictogram, color: AraNoticeColor = .plain, motion: Motion = .none, leading: String? = nil,
        value: Value = .none, valueColor: AraNoticeColor? = nil
    ) {
        self.init(.pictogram(pictogram), color: color, motion: motion, leading: leading, value: value, valueColor: valueColor)
    }

    // MARK: Measures, in the layout's points

    static let iconSize: CGFloat = 17
    static let gap: CGFloat = 6
    static let meterWidth: CGFloat = 46
    static let cellCount = 5
    static let longestText: CGFloat = 120

    private static func width(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return min(ceil((text as NSString).size(withAttributes: [.font: font]).width), longestText)
    }

    var leadingWidth: CGFloat {
        Self.iconSize + (leading.map { Self.gap + Self.width($0) } ?? 0)
    }

    var valueWidth: CGFloat {
        switch value {
        case .none: 0
        case .meter: Self.meterWidth
        case .cells: CGFloat(Self.cellCount) * 6 + CGFloat(Self.cellCount - 1) * 3
        case .ring, .pictogram: Self.iconSize
        case .light: 8
        case .done: Self.iconSize
        case let .text(text): Self.width(text)
        case .swatch: 16
        case .picture: 22
        case let .count(n): CGFloat(min(max(n, 1), 9)) * 8
        }
    }

    /// The room on each side of the camera: the wider side's, so both are the same.
    public var sideWidth: CGFloat {
        (max(leadingWidth, valueWidth, 18) + 2 * ActivityWings.padding + 4).rounded(.up)
    }
}

public extension NotchLiveActivity {
    /// A notice that reads at a glance beside the closed notch (`AraGlance`). `detail` is said
    /// to VoiceOver and shown under the notch while the pointer rests on it, where the notch
    /// opens only on a click.
    @MainActor
    init(
        id: String, priority: Int, duration: TimeInterval, pageID: String? = nil, glance: AraGlance,
        detail: String? = nil, onClick: (@MainActor () -> Void)? = nil
    ) {
        self.init(id: id, priority: priority, duration: duration, pageID: pageID) {
            AraGlanceLeading(glance: glance)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(detail ?? "")
        } trailing: {
            AraGlanceValue(glance: glance)
        }
        sideWidth = glance.sideWidth
        peek = detail
        self.onClick = onClick
    }
}

/// The left of a glance: the pictogram, moving if it should, and any words beside it.
struct AraGlanceLeading: View {
    let glance: AraGlance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var beat = AraBeat()

    var body: some View {
        HStack(spacing: AraGlance.gap) {
            icon
                .foregroundStyle(glance.color.color)
                .modifier(AraGlanceMotion(motion: reduceMotion ? .none : glance.motion, phase: beat.phase))
            if let leading = glance.leading {
                Text(leading)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.ink)
                    .lineLimit(1)
            }
        }
        .onAppear { if glance.motion != .none, !reduceMotion { beat.start() } }
        .onDisappear { beat.stop() }
    }

    @ViewBuilder
    private var icon: some View {
        switch glance.icon {
        case let .pictogram(p):
            AraPictogramView(p, size: AraGlance.iconSize)
        case let .image(image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: AraGlance.iconSize, height: AraGlance.iconSize)
        }
    }
}

/// The right of a glance: how much, or which.
struct AraGlanceValue: View {
    let glance: AraGlance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var beat = AraBeat()

    private var tint: Color { (glance.valueColor ?? glance.color).color }

    var body: some View {
        switch glance.value {
        case .none:
            EmptyView()
        case let .meter(level):
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: AraGlance.meterWidth * min(max(level, 0), 1))
            }
            .frame(width: AraGlance.meterWidth, height: 5)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: level)
        case let .cells(lit):
            HStack(spacing: 3) {
                ForEach(0..<AraGlance.cellCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(index < lit ? tint : Color.white.opacity(0.2))
                        .frame(width: 6, height: 11)
                }
            }
        case let .ring(fraction):
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.6)
                Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 15, height: 15)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        case let .light(beating):
            Circle().fill(tint).frame(width: 8, height: 8)
                .modifier(AraGlanceMotion(motion: beating && !reduceMotion ? .pulse : .none, phase: beat.phase))
                .onAppear { if beating, !reduceMotion { beat.start() } }
                .onDisappear { beat.stop() }
        case .done:
            AraPictogramView(.done, size: AraGlance.iconSize).foregroundStyle(tint)
        case let .pictogram(p):
            AraPictogramView(p, size: AraGlance.iconSize).foregroundStyle(tint)
        case let .text(text):
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(glance.valueColor.map(\.color) ?? AraPalette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: AraGlance.longestText, alignment: .trailing)
        case let .swatch(color):
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .frame(width: 16, height: 16)
        case let .picture(image):
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 22, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        case let .count(n):
            HStack(spacing: 3) {
                ForEach(0..<min(max(n, 1), 9), id: \.self) { _ in
                    Circle().fill(tint).frame(width: 5, height: 5)
                }
            }
        }
    }
}

/// Keeps time for a pictogram that moves.
@MainActor
final class AraBeat: ObservableObject {
    @Published var phase: Double = 0
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.phase += 1.0 / 30 }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// The motions a pictogram can make, from the time since it showed.
struct AraGlanceMotion: ViewModifier {
    let motion: AraGlance.Motion
    let phase: Double

    func body(content: Content) -> some View {
        switch motion {
        case .none:
            content
        case .pulse:
            let swell = 0.5 - 0.5 * cos(phase * 2 * .pi / 1.4)
            content.scaleEffect(1 + 0.3 * swell).opacity(1 - 0.45 * swell)
        case .blink:
            content.opacity(0.4 + 0.6 * (0.5 + 0.5 * cos(phase * 2 * .pi / 1.6)))
        case .shake:
            // A ring of the bell every 1.6 seconds.
            let t = phase.truncatingRemainder(dividingBy: 1.6)
            let angle = t < 0.5 ? 14 * sin(t * 4 * 2 * .pi) * (1 - t / 0.5) : 0
            content.rotationEffect(.degrees(angle), anchor: .top)
        case .spin:
            content.rotationEffect(.degrees(phase * 260))
        case .drop:
            // Drops in once, from above.
            let t = min(phase / 0.45, 1)
            content.offset(y: -6 * (1 - t) * (1 - t)).opacity(t)
        }
    }
}
