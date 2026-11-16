import NotchCore
import SwiftUI

/// The notch itself: a black shape that grows from the notch into the open panel, with round
/// buttons that pour out around it while it is open.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let openEarRadius: CGFloat = 8
    /// The margin around every page, on the sheet before enlargement.
    static let contentPadding: CGFloat = 14

    var body: some View {
        ZStack(alignment: .top) {
            shape
            backdrop
                .frame(width: model.openSize.width, height: model.openSize.height)
                .mask(alignment: .top) { outline }
                .opacity(model.isOpen ? 1 : 0)
            content
                // The page grows out of the notch as it opens, and sinks back into it.
                .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.86, anchor: .top)
                .blur(radius: model.isOpen || reduceMotion ? 0 : 6)
                .mask(alignment: .top) { outline }
                .opacity(model.isOpen ? 1 : 0)
                .allowsHitTesting(model.isOpen)
                .contextMenu { islandMenu }
            dropFill
            activityContent
            peek
        }
        .frame(width: model.openSize.width, height: model.openSize.height, alignment: .top)
        .overlay(alignment: .topLeading) {
            NotchOrbits(model: model)
        }
        .background(alignment: .topLeading) { sideMeasure }
        // Over a full-screen app the notch is out of the way until it has a notice to give.
        .opacity(model.isHiddenForFullScreen ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: model.isHiddenForFullScreen)
        // The window is larger than the notch, for the buttons around it and the overshoot of
        // its spring: the notch stays hung from the top, in the middle.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // It grows with a little bounce and shrinks without one, so closing is firm.
        .animation(Self.spring(growing: model.isOpen, reduceMotion: reduceMotion), value: model.isOpen)
        .animation(Self.spring(growing: model.lastChangeGrew, reduceMotion: reduceMotion), value: model.openSize)
        .animation(Self.spring(growing: true, reduceMotion: reduceMotion), value: model.isExploring)
        // The swell under the pointer springs out with a little overshoot.
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: model.isTouched)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: model.isActivityHovered)
        .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0), value: model.measuredSideWidth)
        // A notice opens and closes smoothly, without a bounce: an overshoot of the plate read
        // as a jolt.
        .animation(Self.noticeMotion, value: model.activity?.request.id)
        // The notch is the night sheet whatever the appearance of the rest of the app.
        .environment(\.colorScheme, .dark)
    }

    static func spring(growing: Bool, reduceMotion: Bool) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.2) }
        let spring = NotchMotion.spring(growing: growing)
        return .spring(duration: spring.duration, bounce: spring.bounce)
    }

    /// The open notch is drawn on glass: the shape lets it show instead of filling black.
    private var opensOnGlass: Bool {
        model.isOpen && model.material != .black
    }

    /// The notch's outline, for masking what is drawn in it: always opaque, whatever the notch
    /// is laid on, since a mask keeps only where it is filled.
    private var outline: some View {
        notchShape(fill: .black)
    }

    private var shape: some View {
        notchShape(fill: opensOnGlass ? .clear : .black)
    }

    @ViewBuilder
    private func notchShape(fill: Color) -> some View {
        let size = model.isOpen ? model.openSize : closedShapeSize
        if model.isPill {
            // Floating free of the screen edge: round on every corner, a capsule when closed.
            RoundedRectangle(cornerRadius: model.isOpen ? 22 : min(size.height / 2, 18), style: .continuous)
                .fill(fill)
                .frame(width: size.width, height: size.height)
        } else {
            NotchShape(
                // The closed shape must hide entirely behind the hardware notch, so no ears there.
                bottomRadius: model.isOpen ? 22 : (isDropping ? 14 : 10),
                earRadius: model.isOpen ? Self.openEarRadius : 0)
                .fill(fill)
                .frame(width: size.width, height: size.height)
        }
    }

    /// What a notice that dropped out of the notch is filled with: drawn in the grown notch's
    /// own outline, and black where the notch itself is, fading out all round it, so that the
    /// two are one and the grown notch's top corners still keep their colour.
    @ViewBuilder
    private var dropFill: some View {
        if isDropping, let fill = model.activity?.dropFill {
            let size = closedShapeSize
            fill()
                .frame(width: size.width, height: size.height)
                // The fill takes the plate's full size at once and the growing shape reveals
                // it. Grown along with the shape, the rays were built anew on every frame of
                // the opening, and their unrolling started over each time.
                .transaction { $0.animation = nil }
                .overlay(alignment: .top) {
                    let notch = model.closedSize
                    EllipticalGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.68), .init(color: .clear, location: 1)],
                        center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                        .frame(width: notch.width * 1.5, height: notch.height * 3)
                        .offset(y: -notch.height * 1.5)
                }
                .mask(alignment: .top) { outline }
                .opacity(model.isNoticeLeaving ? 0 : 1)
                .animation(Self.noticeFade, value: model.isNoticeLeaving)
                .transition(Self.noticeContent)
                .id(model.activity?.request.id)
        }
    }

    /// The closed shape: a thin bar while it waits where there is no hardware notch, widened
    /// on both sides while a live activity is showing, and a little larger all round while
    /// the pointer is on it.
    private var closedShapeSize: CGSize {
        var size = model.closedSize
        if let card = model.activity?.dropSize {
            // A notice that drops out of the notch: downwards, and hardly sideways.
            size = NotchDropLayout.shapeSize(closed: size, card: card, scale: model.scale)
        } else if model.activity != nil {
            size.width += 2 * model.shownActivitySideWidth
            size.height += model.shownActivityBottomHeight
        } else if !model.isTouched, let idle = model.idleSize {
            // Nothing to show and nothing on it: the notch waits as a thin bar.
            size = idle
        }
        if model.isTouched {
            size.width += Self.touchSwell.width
            size.height += Self.touchSwell.height + (peekText == nil ? 0 : Self.peekHeight)
        }
        return size
    }

    /// The closed notch is showing a notice as a card under it.
    private var isDropping: Bool {
        !model.isOpen && model.activity?.dropSize != nil
    }

    private static let touchSwell = CGSize(width: 6, height: 3)

    /// How the notch grows into a notice and back.
    static let noticeMotion = Animation.timingCurve(0.22, 0.8, 0.3, 1, duration: 0.3)
    /// What is on a notice fades before the plate shrinks back.
    static let noticeFade = Animation.easeIn(duration: 0.12)
    static let noticeFadeTime: TimeInterval = 0.13

    /// What is on a notice comes once the plate has nearly grown, and goes at once as it shrinks,
    /// so no text or colour shows beyond the black while it moves.
    static let noticeContent = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.16).delay(0.14)),
        removal: .opacity.animation(.easeIn(duration: 0.12)))
    private static let peekHeight: CGFloat = 20

    /// The activity's extra line, while the notch is touched and opens only on a click.
    private var peekText: String? {
        guard model.isTouched, model.allowsPeek, !model.isOpen else { return nil }
        return model.activity?.peek
    }

    @ViewBuilder
    private var peek: some View {
        if let peekText {
            Text(peekText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AraPalette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(width: closedShapeSize.width, height: Self.peekHeight)
                .padding(.top, model.closedSize.height + model.shownActivityBottomHeight + 1)
                .transition(.opacity)
        }
    }

    // MARK: - Beside the closed notch

    /// The live activity's two views, left and right of the hardware notch. Closed state only.
    @ViewBuilder
    private var activityContent: some View {
        if let activity = model.activity, !model.isOpen, let card = activity.dropSize, let drop = activity.drop {
            // The card is laid out at its own size and shown enlarged like the pages.
            let shown = NotchDropLayout.shapeSize(closed: model.closedSize, card: card, scale: model.scale)
            drop()
                .frame(width: card.width, height: card.height)
                .scaleEffect(model.scale)
                .frame(width: shown.width, height: shown.height - model.closedSize.height)
                // Drawn as one picture at the size it is shown: scaled after drawing, its
                // text blurred on displays that are not Retina.
                .drawingGroup()
                .clipped()
                .padding(.top, model.closedSize.height)
                .foregroundStyle(AraPalette.ink)
                // Kept within the black while the plate grows and shrinks.
                .mask(alignment: .top) { outline }
                .opacity(model.isNoticeLeaving ? 0 : 1)
                .animation(Self.noticeFade, value: model.isNoticeLeaving)
                .transition(Self.noticeContent)
                .id(activity.request.id)
        } else if let activity = model.activity, !model.isOpen {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    if let companion = model.companion {
                        activitySide(AnyView(HStack(spacing: 5) { companion.leading(); companion.trailing() }), alignment: .leading)
                    } else {
                        activitySide(activity.leading(), alignment: .leading)
                    }
                    Color.clear.frame(width: model.closedSize.width)
                    if model.companion != nil {
                        activitySide(AnyView(HStack(spacing: 5) { activity.leading(); activity.trailing() }), alignment: .trailing)
                    } else {
                        activitySide(activity.trailing(), alignment: .trailing)
                    }
                }
                .frame(height: model.closedSize.height)
                if let bottom = activity.bottom, model.companion == nil {
                    activityBottom(bottom())
                }
            }
            .environment(\.notchActivityIsHovered, model.isActivityHovered)
            .foregroundStyle(AraPalette.ink)
            .lineLimit(1)
            .transition(.opacity)
            .id(activity.request.id + (model.companion?.request.id ?? ""))
        }
    }

    /// Measures what the sides of the closed notch show, at its natural size, so each side is
    /// as wide as its content (`ActivityWings`).
    @ViewBuilder
    private var sideMeasure: some View {
        if let activity = model.activity, activity.dropSize == nil {
            let scale = model.edgeScale
            HStack(alignment: .top, spacing: 0) {
                Group {
                    if let companion = model.companion {
                        HStack(spacing: 5) { companion.leading(); companion.trailing() }
                    } else {
                        activity.leading()
                    }
                }
                .fixedSize()
                .background(GeometryReader { Color.clear.preference(key: SideWidthKey.self, value: [$0.size.width]) })
                Group {
                    if model.companion != nil {
                        HStack(spacing: 5) { activity.leading(); activity.trailing() }
                    } else {
                        activity.trailing()
                    }
                }
                .fixedSize()
                .background(GeometryReader { Color.clear.preference(key: SideWidthKey.self, value: [$0.size.width]) })
            }
            .frame(height: model.closedSize.height / scale)
            .hidden()
            .allowsHitTesting(false)
            .onPreferenceChange(SideWidthKey.self) { widths in
                let widest = (widths.max() ?? 0) * scale
                let width = ActivityWings.width(content: widest, combined: model.companion != nil)
                if model.measuredSideWidth != width {
                    model.measuredSideWidth = width
                }
            }
        }
    }

    /// One side of a live activity: laid out at its own size and shown enlarged with the
    /// rest of the notch, as far as the height of the hardware notch allows.
    private func activitySide(_ view: AnyView, alignment: Alignment) -> some View {
        let scale = model.edgeScale
        let padding = ActivityWings.padding
        let width = max(model.shownActivitySideWidth - 2 * padding, 1)
        return view
            .frame(width: width / scale, height: model.closedSize.height / scale, alignment: alignment)
            .scaleEffect(scale)
            .frame(width: width, height: model.closedSize.height)
            .drawingGroup()
            .padding(.horizontal, padding)
    }

    /// The strip under the hardware notch, across the notch and its sides, enlarged like the
    /// sides. Not drawn as one picture, so a glow on it is not cut at the strip's edge.
    private func activityBottom(_ view: AnyView) -> some View {
        let scale = model.edgeScale
        let height = model.shownActivityBottomHeight
        let width = model.closedSize.width + 2 * model.shownActivitySideWidth
        return view
            .frame(width: width / scale, height: height / scale)
            .scaleEffect(scale)
            .frame(width: width, height: height)
    }

    // MARK: - The open notch

    private var content: some View {
        let width = model.openSize.width - 2 * Self.openEarRadius
        let bandHeight = model.closedSize.height
        return VStack(spacing: 0) {
            // The strip beside the camera: the page's name on the left, its own controls on
            // the right. As tall as the hardware notch, so it grows less than the page.
            band(rowWidth: width)
                .frame(width: width, height: bandHeight)
            // The page is laid out at the size it is shown, every measure multiplied by the
            // notch's size, so text is drawn sharp on any display.
            page
                .environment(\.araScale, model.scale)
                .frame(width: width, height: max(model.openSize.height - bandHeight, 0))
        }
        .frame(width: width, height: model.openSize.height)
        // Cards on the notch are white of a few strengths over whatever the notch is laid on,
        // black or glass, never a grey of their own.
        .environment(\.araOnNotch, true)
    }

    /// What every page is laid on.
    private var backdrop: some View {
        NotchBackdrop(material: model.material, bandHeight: model.closedSize.height)
    }

    private static let bandPadding: CGFloat = 14
    /// Kept clear on each side of the hardware notch.
    private static let notchGap: CGFloat = 6

    /// The strip beside the camera. The hardware notch hides whatever is drawn behind it, so
    /// nothing is.
    private func band(rowWidth: CGFloat) -> some View {
        let grow = model.edgeScale
        let notchWidth = model.hasPhysicalNotch ? model.closedSize.width : 0
        let side = CGFloat(TabRowLayout.sideWidth(
            rowWidth: Double(rowWidth), notchWidth: Double(notchWidth), edgePadding: Double(Self.bandPadding * grow),
            notchGap: Double(Self.notchGap * grow)))
        let page = model.registry.selectedID.flatMap { model.pages[$0] }
        return HStack(spacing: 0) {
            HStack(spacing: 6 * grow) {
                if model.isExploring {
                    bandTitle(symbol: "square.grid.2x2", title: L10n.string("notch.explore"), hue: nil, glyph: nil)
                } else if let leading = page?.bandLeading {
                    leading()
                } else if let page {
                    bandTitle(
                        symbol: page.descriptor.symbolName, title: L10n.string(page.descriptor.titleKey), hue: page.hue,
                        glyph: AraGlyph(pageID: page.id))
                }
                Spacer(minLength: 0)
            }
            .frame(width: side)
            Color.clear.frame(width: notchWidth + 2 * Self.notchGap * grow)
            HStack(spacing: 4 * grow) {
                Spacer(minLength: 0)
                if !model.isExploring, let accessory = page?.headerAccessory {
                    accessory()
                }
                if model.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10 * grow, weight: .semibold))
                        .foregroundStyle(AraPalette.ink.opacity(0.7))
                        .help(L10n.string("notch.pin.on"))
                }
            }
            .frame(width: side)
        }
        .padding(.horizontal, Self.bandPadding * grow)
        .environment(\.araScale, grow)
    }

    private func bandTitle(symbol: String, title: String, hue: AraHue?, glyph: AraGlyph?) -> some View {
        let grow = model.edgeScale
        return HStack(spacing: 6 * grow) {
            Group {
                if let glyph {
                    AraGlyphView(glyph, size: 13)
                } else {
                    Image(systemName: symbol).font(.system(size: 11 * grow, weight: .semibold))
                }
            }
            .foregroundStyle(hue.map { AraPalette.tint($0).line } ?? AraPalette.ink.opacity(0.8))
            Text(title)
                .font(.system(size: 12 * grow, weight: .medium))
                .foregroundStyle(AraPalette.ink.opacity(0.62))
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var page: some View {
        Group {
            if model.isExploring {
                NotchExploreGrid(model: model)
                    .transition(.opacity)
            } else if let id = model.registry.selectedID, let page = model.pages[id] {
                page.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .araHue(page.hue)
                    .id(id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Self.contentPadding * model.scale)
        .padding(.top, 4 * model.scale)
        .padding(.bottom, Self.contentPadding * model.scale)
        .foregroundStyle(AraPalette.ink)
        .animation(.easeInOut(duration: 0.18), value: model.registry.selectedID)
        .animation(.easeInOut(duration: 0.18), value: model.isExploring)
    }

    /// The menu of the open notch, on a secondary click anywhere on it: what used to sit on
    /// its tab row, out of the way.
    @ViewBuilder
    private var islandMenu: some View {
        Button(L10n.string(model.isPinned ? "notch.pin.on" : "notch.pin.off")) { model.onTogglePin?() }
        Button(L10n.string("notch.explore")) { model.onOrbit?(.explore) }
        Button(L10n.string("notch.settings.tooltip")) { model.onOpenSettings?() }
        Divider()
        Button(L10n.string("notch.close")) { model.onClose?() }
    }
}

private struct SideWidthKey: PreferenceKey {
    static let defaultValue: [CGFloat] = []
    static func reduce(value: inout [CGFloat], nextValue: () -> [CGFloat]) {
        value += nextValue()
    }
}

/// A button of the page's own in the strip right of the camera: an icon, its name under the
/// pointer, filled while it is on. For a page's `headerAccessory`.
public struct NotchToolbarButton: View {
    let symbolName: String
    let title: String
    let isOn: Bool
    let action: () -> Void
    @StateObject private var hover = AraHover()
    @Environment(\.araScale) private var ui

    public init(symbolName: String, title: String, isOn: Bool, action: @escaping () -> Void) {
        self.symbolName = symbolName
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button {
            AraTooltipCenter.shared.hide()
            action()
        } label: {
            Image(systemName: symbolName)
                .font(.system(size: 12 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.ink.opacity(isOn || hover.isHovered ? 1 : 0.6))
                .frame(width: 28 * ui, height: 24 * ui)
                .background {
                    RoundedRectangle(cornerRadius: 8 * ui, style: .continuous)
                        .fill(Color.white.opacity(isOn ? 0.14 : (hover.isHovered ? 0.09 : 0)))
                }
                .contentShape(Rectangle())
                .animation(AraTheme.hover, value: hover.isHovered)
        }
        .buttonStyle(AraPressStyle())
        .onHover { hover.isHovered = $0 }
        .araTooltip(title, isHovered: hover.isHovered)
        .accessibilityLabel(title)
    }
}
