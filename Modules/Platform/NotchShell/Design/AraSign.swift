import AppKit
import CoreImage
import NotchCore
import SwiftUI

/// A notice written like a wayfinding sign: on the left what speaks (an icon, its name and
/// perhaps a line about it), a hairline, and on the right the news in one or two rows, each
/// a label with, where it helps, a small line under it and a box of digits or a disc.
///
/// The sign is one piece with the notch: the closed notch grows downwards and sideways into
/// it. It has no frame; it is lit by rays of colour from its two top corners, in the colours
/// of the kind of news it is, and is black at the top only where the notch itself is.
public struct AraSign {
    /// What kind of news it is; the colours of the rays the sign is lit with follow it.
    public enum Tone: Sendable {
        /// News with no urgency: the whole palette, violet, blue and teal against orange, pink and gold.
        case plain
        /// Something is at work: blues and violets.
        case working
        /// Something wants the user: magenta through pink to orange.
        case attention
        /// Something went wrong or is running out: reds.
        case danger

        /// The colour of a disc on the sign.
        var color: Color {
            switch self {
            case .plain: AraPalette.ink
            case .working: Color(red: 0.78, green: 0.70, blue: 1)
            case .attention: Color(red: 1, green: 0.78, blue: 0.45)
            case .danger: Color(red: 1, green: 0.55, blue: 0.5)
            }
        }

        private static func rgb(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }

        /// The colours of the rays, as 0xRRGGBB: the left corner's three, then the right corner's.
        var rayColors: [UInt32] {
            switch self {
            case .plain: [0xC44BFF, 0x2A8CF0, 0x19E0DA, 0xFF7A59, 0xFF4F8B, 0xFFD36A]
            case .working: [0x8A5BFF, 0x2A8CF0, 0x19C8E0, 0xB45CFF, 0x3B6BFF, 0x5AD1FF]
            case .attention: [0xC44BFF, 0xFF5C8A, 0xFF9A4C, 0xFFB04C, 0xFF4F8B, 0xD05BFF]
            case .danger: [0xFF3B3B, 0xFF2D6A, 0xFF7A59, 0xFF5A36, 0xFF2D55, 0xFF9A4C]
            }
        }

        /// The colour of the glow along the sign's bottom edge.
        var glow: Color {
            switch self {
            case .plain: Self.rgb(0x3B2BD6)
            case .working: Self.rgb(0x2D3BDB)
            case .attention: Self.rgb(0xB23FD0)
            case .danger: Self.rgb(0xB3122E)
            }
        }
    }

    public enum Icon {
        case symbol(String)
        case image(NSImage)
    }

    /// A value set apart at the end of a row.
    public enum Badge: Equatable {
        /// Digits in a dark box, like a departure board.
        case digits(String)
        /// A short value on a disc in the sign's colour.
        case disc(String)
    }

    /// One row of the news.
    public struct Row {
        var label: String
        var detail: String?
        var badge: Badge?
        /// 0…1: a bar before the badge, for a level such as the volume.
        var level: Double?

        public init(_ label: String, detail: String? = nil, badge: Badge? = nil, level: Double? = nil) {
            self.label = label
            self.detail = detail
            self.badge = badge
            self.level = level
        }
    }

    var tone: Tone
    var icon: Icon
    /// The name of what speaks, set like a logo.
    var mark: String
    var markDetail: String?
    /// A line beside the name, with a small one under it: what it is doing.
    var title: String?
    var subtitle: String?
    var rows: [Row]
    /// An arrow closes each row when a click on the sign leads somewhere.
    var leadsSomewhere = false

    public init(
        tone: Tone = .plain, icon: Icon, mark: String, markDetail: String? = nil, title: String? = nil,
        subtitle: String? = nil, rows: [Row] = []
    ) {
        self.tone = tone
        self.icon = icon
        self.mark = mark
        self.markDetail = markDetail
        self.title = title
        self.subtitle = subtitle
        self.rows = Array(rows.prefix(2))
    }

    // MARK: - Measures

    // The fonts the sign is drawn in, for measuring its lines before it is drawn.
    private static var markFont: NSFont { .systemFont(ofSize: 13, weight: .semibold) }
    private static var titleFont: NSFont { .systemFont(ofSize: 12, weight: .semibold) }
    private static var labelFont: NSFont { .systemFont(ofSize: 11.5, weight: .medium) }
    private static var smallFont: NSFont { .systemFont(ofSize: 9.5, weight: .regular) }
    private static var digitsFont: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .semibold) }
    static let edge: CGFloat = 14
    static let iconWidth: CGFloat = 18
    static let levelWidth: CGFloat = 76
    /// The longest a line of text is laid out; longer ones are cut with an ellipsis.
    static let maxTextWidth: CGFloat = 170

    private static func width(_ text: String?, _ font: NSFont) -> CGFloat {
        guard let text, !text.isEmpty else { return 0 }
        return min(ceil((text as NSString).size(withAttributes: [.font: font]).width), maxTextWidth)
    }

    static func badgeWidth(_ badge: Badge?) -> CGFloat {
        switch badge {
        case nil: 0
        case .digits(let text): max(width(text, digitsFont) + 12, 34)
        case .disc(let text): max(width(text, digitsFont) + 10, 20)
        }
    }

    func rowWidth(_ row: Row) -> CGFloat {
        var width = max(Self.width(row.label, Self.labelFont), Self.width(row.detail, Self.smallFont))
        if row.level != nil { width += 8 + Self.levelWidth }
        if row.badge != nil { width += 8 + Self.badgeWidth(row.badge) }
        if leadsSomewhere { width += 6 + 12 }
        return width
    }

    var leftWidth: CGFloat {
        var width = Self.edge + Self.iconWidth + 8 + max(Self.width(mark, Self.markFont), Self.width(markDetail, Self.smallFont))
        let text = max(Self.width(title, Self.titleFont), Self.width(subtitle, Self.smallFont))
        if text > 0 { width += 10 + text }
        return width + Self.edge
    }

    var rightWidth: CGFloat {
        guard let widest = rows.map(rowWidth).max() else { return 0 }
        return Self.edge + widest + Self.edge
    }

    /// The sign's size on the sheet the pages are drawn on.
    public var size: CGSize {
        CGSize(
            width: NotchSignLayout.width(left: leftWidth, right: rightWidth),
            height: NotchSignLayout.height(
                leftHasSmallLine: markDetail != nil || subtitle != nil, rowsWithSmallLine: rows.map { $0.detail != nil }))
    }
}

public extension NotchLiveActivity {
    /// A notice shown as a sign that the closed notch grows into for a while.
    /// - Parameters:
    ///   - pageID: the page a click on the sign opens; its rows then end in an arrow.
    ///   - onClick: what a click on the sign does instead, such as taking something back.
    @MainActor
    init(
        id: String, priority: Int, duration: TimeInterval, pageID: String? = nil, sign: AraSign,
        onClick: (@MainActor () -> Void)? = nil
    ) {
        var sign = sign
        sign.leadsSomewhere = pageID != nil || onClick != nil
        let shown = sign
        let tone = sign.tone
        self.init(
            id: id, priority: priority, duration: duration, pageID: pageID, dropSize: sign.size,
            fill: { AnyView(AraSignRays(tone: tone)) }
        ) {
            AraSignView(sign: shown)
        }
        self.onClick = onClick
    }
}

/// The light a sign is filled with: rays of colour from its two top corners that unroll as
/// the sign opens and then sway, each in its own time, over a glow along its bottom edge.
///
/// Each ray is drawn and blurred once (`AraSignBlades`) and its motion is handed to Core
/// Animation, which plays it on its own: nothing in the notch is drawn again while it moves.
/// Moving the rays from SwiftUI made the whole notch, its hidden pages included, be gone over
/// for every frame, a fifth to a third of a processor core for as long as a sign showed. The
/// rays stand still when the Mac is set to reduce motion or is in Low Power Mode.
struct AraSignRays: View {
    let tone: AraSign.Tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { area in
            ZStack {
                EllipticalGradient(
                    colors: [tone.glow.opacity(0.4), tone.glow.opacity(0)], center: UnitPoint(x: 0.5, y: 1.15),
                    startRadiusFraction: 0, endRadiusFraction: 0.9)
                AraSignRayLayers(
                    colors: tone.rayColors, size: area.size, scale: displayScale,
                    isStill: reduceMotion || ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        }
        // A thin veil keeps the text clear where a ray passes behind it.
        .overlay(Color.black.opacity(0.14))
    }
}

/// The rays as Core Animation layers, set going once.
struct AraSignRayLayers: NSViewRepresentable {
    let colors: [UInt32]
    let size: CGSize
    let scale: CGFloat
    let isStill: Bool

    func makeNSView(context: Context) -> AraSignRayView {
        AraSignRayView()
    }

    func updateNSView(_ view: AraSignRayView, context: Context) {
        view.show(colors: colors, size: size, scale: scale, isStill: isStill)
    }
}

final class AraSignRayView: NSView {
    /// What the layers were built for; they are built again only when it changes.
    private var shown: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Only to be looked at: a click goes to the notch underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func show(colors: [UInt32], size: CGSize, scale: CGFloat, isStill: Bool) {
        guard size.width > 0, size.height > 0, let root = layer else { return }
        let key = "\(colors)|\(Int(size.width))x\(Int(size.height))|\(scale)|\(isStill)"
        guard key != shown else { return }
        shown = key
        root.sublayers?.forEach { $0.removeFromSuperlayer() }

        let layout = SignRayLayout(signSize: size)
        let blades = AraSignBlades.pictures(colors: colors, layout: layout, scale: scale)
        // Measured upwards from the bottom here, as this view's layers are; the sign's layout
        // is measured down from the top.
        let anchor = CGPoint(x: layout.anchor.x, y: 1 - layout.anchor.y)
        let bounds = CGRect(origin: .zero, size: layout.imageSize)
        for (index, picture) in blades.enumerated() {
            let ray = SignRays.still[index]
            let swing = SignRays.swing(of: index)
            // A left ray turns its foot towards the middle, anticlockwise; a right one clockwise.
            let turn: Double = ray.isLeft ? 1 : -1
            let pivot = layout.pivot(isLeft: ray.isLeft)

            // The holder unrolls the ray as the sign opens; the blade inside it swings.
            let holder = CALayer()
            holder.bounds = bounds
            holder.anchorPoint = anchor
            holder.position = CGPoint(x: pivot.x, y: size.height - pivot.y)
            let blade = CALayer()
            blade.bounds = bounds
            blade.anchorPoint = anchor
            blade.position = CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height)
            blade.contents = picture
            blade.contentsScale = scale
            blade.compositingFilter = "screenBlendMode"
            holder.addSublayer(blade)
            root.addSublayer(holder)

            blade.setValue(turn * ray.angle * .pi / 180, forKeyPath: "transform.rotation.z")
            blade.opacity = Float(ray.brightness)
            guard !isStill else { continue }

            let unrolled = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)
            holder.add(Self.once("transform.scale.y", from: 0.1, to: 1, timing: unrolled), forKey: "unroll")
            holder.add(Self.once("opacity", from: 0, to: 1, timing: unrolled), forKey: "light")
            blade.add(Self.swinging("transform.rotation.z",
                from: turn * swing.angles.lowerBound * .pi / 180, to: turn * swing.angles.upperBound * .pi / 180,
                swing: swing), forKey: "turn")
            blade.add(Self.swinging("transform.scale.y",
                from: swing.lengths.lowerBound, to: swing.lengths.upperBound, swing: swing), forKey: "stretch")
            blade.add(Self.swinging("opacity",
                from: swing.brightness.lowerBound, to: swing.brightness.upperBound, swing: swing), forKey: "glow")
        }
    }

    private static func once(_ keyPath: String, from: Double, to: Double, timing: CAMediaTimingFunction) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = SignRays.unrollTime
        animation.timingFunction = timing
        return animation
    }

    /// There and back between two values for as long as the layer lives: half the period each
    /// way, easing at the ends as a swing does, from `lead` seconds into the swing.
    private static func swinging(_ keyPath: String, from: Double, to: Double, swing: SignRays.Swing) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = swing.period / 2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timeOffset = swing.lead
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}

/// The rays of a sign, drawn and blurred once for each size of sign and kept.
@MainActor
enum AraSignBlades {
    private static var drawn: [String: [CGImage]] = [:]
    private static let imaging = CIContext(options: [.cacheIntermediates: false])

    static func pictures(colors: [UInt32], layout: SignRayLayout, scale: CGFloat) -> [CGImage] {
        let key = "\(colors)|\(Int(layout.signSize.width))|\(scale)"
        if let found = drawn[key] { return found }
        let pictures = colors.compactMap { blade(color: $0, layout: layout, scale: scale) }
        // Signs come in a handful of sizes; a long-running app does not need to keep them all.
        if drawn.count >= 24 { drawn.removeAll() }
        drawn[key] = pictures
        return pictures
    }

    /// A long blade of one colour, solid from its top to two fifths of its length and fading
    /// out at its end, blurred.
    private static func blade(color: UInt32, layout: SignRayLayout, scale: CGFloat) -> CGImage? {
        let size = layout.imageSize
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: Int((size.width * scale).rounded(.up)), height: Int((size.height * scale).rounded(.up)),
            bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Drawn top down, as the sign is laid out.
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: 0, y: -size.height)
        let red = CGFloat((color >> 16) & 0xFF) / 255, green = CGFloat((color >> 8) & 0xFF) / 255, blue = CGFloat(color & 0xFF) / 255
        let solid = CGColor(colorSpace: space, components: [red, green, blue, 1]) ?? CGColor(gray: 1, alpha: 1)
        let clear = CGColor(colorSpace: space, components: [red, green, blue, 0]) ?? CGColor(gray: 1, alpha: 0)
        guard let gradient = CGGradient(colorsSpace: space, colors: [solid, solid, clear] as CFArray, locations: [0, 0.4, 1])
        else { return nil }
        let top = layout.margin + layout.length * 0.08
        context.addEllipse(in: CGRect(x: layout.margin, y: layout.margin, width: layout.breadth, height: layout.length * 1.08))
        context.clip()
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: top + layout.length),
            options: [.drawsBeforeStartLocation])
        guard let sharp = context.makeImage() else { return nil }
        let input = CIImage(cgImage: sharp)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: layout.blur * scale).cropped(to: input.extent)
        return imaging.createCGImage(blurred, from: input.extent)
    }
}

/// The sign as drawn: two zones over its rays of colour, parted by a hairline.
struct AraSignView: View {
    let sign: AraSign

    var body: some View {
        HStack(spacing: 0) {
            left
                .padding(.horizontal, AraSign.edge)
                .frame(width: sign.rightWidth > 0 ? sign.leftWidth : nil, alignment: .leading)
            if !sign.rows.isEmpty {
                Rectangle()
                    .fill(AraPalette.ink.opacity(0.35))
                    .frame(width: 1)
                    .padding(.vertical, 8)
                VStack(alignment: .trailing, spacing: NotchSignLayout.rowSpacing) {
                    ForEach(Array(sign.rows.enumerated()), id: \.offset) { index, row in
                        // A row with a value leads somewhere of its own; of plain lines, the last.
                        self.row(row, hasArrow: row.badge != nil || index == sign.rows.count - 1)
                    }
                }
                .padding(.horizontal, AraSign.edge)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .lineLimit(1)
        // The text stands on light that moves: a tight shadow keeps its edge without a halo.
        .shadow(color: .black.opacity(0.55), radius: 0.6, y: 0.5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var left: some View {
        HStack(spacing: 8) {
            Group {
                switch sign.icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AraPalette.ink)
                case .image(let image):
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: AraSign.iconWidth, height: AraSign.iconWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .frame(width: AraSign.iconWidth)
            stack(sign.mark, .system(size: 13, weight: .semibold), sign.markDetail)
            if let title = sign.title {
                stack(title, .system(size: 12, weight: .semibold), sign.subtitle)
                    .padding(.leading, 2)
            }
        }
    }

    /// A line with, when there is one, a small line under it.
    private func stack(_ text: String, _ font: Font, _ small: String?, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(text)
                .font(font)
                .foregroundStyle(AraPalette.ink)
                .frame(height: NotchSignLayout.lineHeight)
            if let small, !small.isEmpty {
                Text(small)
                    .font(.system(size: 9.5))
                    .foregroundStyle(AraPalette.ink.opacity(0.78))
                    .frame(height: NotchSignLayout.smallLineHeight)
            }
        }
        .frame(maxWidth: AraSign.maxTextWidth, alignment: alignment == .leading ? .leading : .trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func row(_ row: AraSign.Row, hasArrow: Bool) -> some View {
        HStack(spacing: 8) {
            stack(row.label, .system(size: 11.5, weight: .medium), row.detail, alignment: .trailing)
            if let level = row.level {
                ZStack(alignment: .leading) {
                    Capsule().fill(AraPalette.track)
                    Capsule().fill(AraPalette.ink).frame(width: AraSign.levelWidth * min(max(level, 0), 1))
                }
                .frame(width: AraSign.levelWidth, height: 5)
            }
            switch row.badge {
            case .digits(let text):
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AraPalette.value)
                    .frame(width: AraSign.badgeWidth(row.badge), height: 17)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            case .disc(let text):
                Text(text)
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                    .frame(width: AraSign.badgeWidth(row.badge), height: 17)
                    .background(sign.tone.color, in: Capsule())
            case nil:
                EmptyView()
            }
            if sign.leadsSomewhere {
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AraPalette.ink.opacity(0.9))
                    .frame(width: 12)
                    .opacity(hasArrow ? 1 : 0)
            }
        }
    }
}

/// A sign set inside an open page rather than dropped out of the closed notch, for a notice
/// that must be seen while the notch is open, such as the one that takes back a reminder
/// just ticked off. A click on it does what the notice offers.
public struct AraSignBanner: View {
    @Environment(\.araScale) private var ui
    let sign: AraSign
    let action: () -> Void

    public init(sign: AraSign, action: @escaping () -> Void) {
        var sign = sign
        sign.leadsSomewhere = true
        self.sign = sign
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                AraSignRays(tone: sign.tone)
                // Laid out at the sign's own size and drawn as one picture at the size it is
                // shown, as the sign under the notch is.
                AraSignView(sign: sign)
                    .frame(width: sign.size.width, height: sign.size.height)
                    .scaleEffect(ui)
                    .frame(width: sign.size.width * ui, height: sign.size.height * ui)
                    .drawingGroup()
            }
            .frame(width: sign.size.width * ui, height: sign.size.height * ui)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 12 * ui, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12 * ui, style: .continuous))
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
        .environment(\.colorScheme, .dark)
    }
}
