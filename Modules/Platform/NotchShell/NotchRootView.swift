import NotchCore
import SwiftUI

/// The notch itself: a black shape that grows from the notch into the open panel.
struct NotchRootView: View {
    @ObservedObject var model: NotchViewModel
    /// The filled shape under the chosen tab slides from tab to tab.
    @Namespace private var tabSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let openEarRadius: CGFloat = 8
    /// The margin around every page, on the sheet before enlargement.
    static let contentPadding: CGFloat = 14

    var body: some View {
        ZStack(alignment: .top) {
            shape
            backdrop
                .frame(width: model.openSize.width, height: model.openSize.height)
                .mask(alignment: .top) { shape }
                .opacity(model.isOpen ? 1 : 0)
            content
                // The page grows out of the notch as it opens, and sinks back into it.
                .scaleEffect(model.isOpen || reduceMotion ? 1 : 0.86, anchor: .top)
                .blur(radius: model.isOpen || reduceMotion ? 0 : 6)
                .mask(alignment: .top) { shape }
                .opacity(model.isOpen ? 1 : 0)
                .allowsHitTesting(model.isOpen)
            dropFill
            activityContent
            peek
        }
        .frame(width: model.openSize.width, height: model.openSize.height, alignment: .top)
        // Over a full-screen app the notch is out of the way until it has a notice to give.
        .opacity(model.isHiddenForFullScreen ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: model.isHiddenForFullScreen)
        // The window may be taller than the notch for a moment while a page changes its
        // height: the notch stays hung from the top.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: model.isOpen)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: model.openSize)
        // The swell under the pointer springs out with a little overshoot.
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.58), value: model.isTouched)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: model.isActivityHovered)
        // A notice opens and closes smoothly, without a bounce: an overshoot of the plate read
        // as a jolt.
        .animation(Self.noticeMotion, value: model.activity?.request.id)
        // The notch is the night sheet whatever the appearance of the rest of the app.
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var shape: some View {
        let size = model.isOpen ? model.openSize : closedShapeSize
        if model.isPill {
            // Floating free of the screen edge: round on every corner, a capsule when closed.
            RoundedRectangle(cornerRadius: model.isOpen ? 22 : min(size.height / 2, 18), style: .continuous)
                .fill(.black)
                .frame(width: size.width, height: size.height)
        } else {
            NotchShape(
                // The closed shape must hide entirely behind the hardware notch, so no ears there.
                bottomRadius: model.isOpen ? 22 : (isDropping ? 14 : 10),
                earRadius: model.isOpen ? Self.openEarRadius : 0)
                .fill(.black)
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
                .mask(alignment: .top) { shape }
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

    private static let touchSwell = CGSize(width: 10, height: 4)

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

    /// The activity's extra line, while the notch is touched and would not open by itself.
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
                .mask(alignment: .top) { shape }
                .opacity(model.isNoticeLeaving ? 0 : 1)
                .animation(Self.noticeFade, value: model.isNoticeLeaving)
                .transition(Self.noticeContent)
                .id(activity.request.id)
        } else if let activity = model.activity, !model.isOpen {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    activitySide(activity.leading(), alignment: .leading)
                    Color.clear.frame(width: model.closedSize.width)
                    activitySide(activity.trailing(), alignment: .trailing)
                }
                .frame(height: model.closedSize.height)
                if let bottom = activity.bottom {
                    activityBottom(bottom())
                }
            }
            .environment(\.notchActivityIsHovered, model.isActivityHovered)
            .foregroundStyle(AraPalette.ink)
            .lineLimit(1)
            .transition(.opacity)
            .id(activity.request.id)
        }
    }

    /// One side of a live activity: laid out at its own size and shown enlarged with the
    /// rest of the notch, as far as the height of the hardware notch allows.
    private func activitySide(_ view: AnyView, alignment: Alignment) -> some View {
        let scale = model.edgeScale
        let width = model.shownActivitySideWidth - 20
        return view
            .frame(width: width / scale, height: model.closedSize.height / scale, alignment: alignment)
            .scaleEffect(scale)
            .frame(width: width, height: model.closedSize.height)
            .drawingGroup()
            .padding(.horizontal, 10)
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

    private var content: some View {
        let width = model.openSize.width - 2 * Self.openEarRadius
        let headerHeight = model.closedSize.height
        return VStack(spacing: 0) {
            // The tab row is as tall as the hardware notch it sits beside, so it grows less
            // than the page when the largest size is chosen.
            header(rowWidth: width)
                .frame(width: width, height: headerHeight)
            // The page is laid out at the size it is shown, every measure multiplied by the
            // notch's size, so text is drawn sharp on any display.
            page
                .environment(\.araScale, model.scale)
                .frame(width: width, height: model.openSize.height - headerHeight)
        }
        .frame(width: width, height: model.openSize.height)
    }

    /// What every page is laid on.
    private var backdrop: some View {
        AraNotchGround()
    }

    private static let tabWidth: CGFloat = 30
    private static let tabSpacing: CGFloat = 2
    private static let headerPadding: CGFloat = 12
    /// Kept clear on each side of the hardware notch.
    private static let notchGap: CGFloat = 6

    /// Tabs fill the room left of the hardware notch; those that do not fit carry on to its
    /// right, before the pin and the settings button. The notch hides whatever is drawn
    /// behind it, so nothing is.
    private func header(rowWidth: CGFloat) -> some View {
        let pages = model.registry.pages
        // Only a hardware notch hides things; a drawn one is part of the open panel.
        // Laid out at the size it is shown: the row's own measures grow with the notch, the
        // hardware notch is as wide as it is.
        let grow = model.edgeScale
        let notchWidth = model.hasPhysicalNotch ? model.closedSize.width : 0
        let side = CGFloat(TabRowLayout.sideWidth(
            rowWidth: Double(rowWidth), notchWidth: Double(notchWidth), edgePadding: Double(Self.headerPadding * grow),
            notchGap: Double(Self.notchGap * grow)))
        let leftCount = model.hasPhysicalNotch
            ? TabRowLayout.leftCount(
                count: pages.count, sideWidth: Double(side), tabWidth: Double(Self.tabWidth * grow),
                spacing: Double(Self.tabSpacing * grow))
            : pages.count
        return HStack(spacing: 0) {
            HStack(spacing: Self.tabSpacing * grow) {
                ForEach(pages.prefix(leftCount)) { tab($0) }
                if model.hasPhysicalNotch {
                    Spacer(minLength: 0)
                }
            }
            .frame(width: model.hasPhysicalNotch ? side : nil)
            if model.hasPhysicalNotch {
                Color.clear.frame(width: notchWidth + 2 * Self.notchGap * grow)
            }
            HStack(spacing: Self.tabSpacing * grow) {
                ForEach(pages.dropFirst(leftCount)) { tab($0) }
                Spacer(minLength: 0)
                if let id = model.registry.selectedID, let accessory = model.pages[id]?.headerAccessory {
                    accessory()
                }
                NotchTab(
                    glyph: nil, symbolName: model.isPinned ? "pin.fill" : "pin",
                    title: L10n.string(model.isPinned ? "notch.pin.on" : "notch.pin.off"),
                    hue: nil, isSelected: model.isPinned, selection: nil
                ) {
                    model.onTogglePin?()
                }
                NotchTab(
                    glyph: .settings, symbolName: AraIcon.settings.symbolName, title: L10n.string("notch.settings.tooltip"),
                    hue: nil, isSelected: false, selection: tabSelection
                ) {
                    model.onOpenSettings?()
                }
            }
        }
        .padding(.horizontal, Self.headerPadding * grow)
        .environment(\.araScale, grow)
        .animation(AraTheme.settle, value: model.registry.selectedID)
    }

    private func tab(_ descriptor: PageDescriptor) -> some View {
        NotchTab(
            glyph: AraGlyph(pageID: descriptor.id), symbolName: descriptor.symbolName,
            title: L10n.string(descriptor.titleKey), hue: model.pages[descriptor.id]?.hue,
            isSelected: descriptor.id == model.registry.selectedID, selection: tabSelection
        ) {
            model.registry.select(descriptor.id)
        }
    }

    @ViewBuilder
    private var page: some View {
        Group {
            if let id = model.registry.selectedID, let page = model.pages[id] {
                page.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .araHue(page.hue)
                    .id(id)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Self.contentPadding * model.scale)
        .foregroundStyle(AraPalette.ink)
        .animation(.easeInOut(duration: 0.15), value: model.registry.selectedID)
    }
}

/// A button on the notch's tab row that looks like the pin beside it: an icon, its name
/// under the pointer, filled while it is on. For a page's own `headerAccessory`.
public struct NotchToolbarButton: View {
    let symbolName: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    public init(symbolName: String, title: String, isOn: Bool, action: @escaping () -> Void) {
        self.symbolName = symbolName
        self.title = title
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        NotchTab(glyph: nil, symbolName: symbolName, title: title, hue: nil, isSelected: isOn, selection: nil, action: action)
    }
}

/// One tab of the open notch: an icon in its page's colour, which brightens under the
/// pointer and sits on a shape filled with that colour when it is the chosen page.
private struct NotchTab: View {
    /// The app's own drawing for the page; a page without one shows its system symbol.
    let glyph: AraGlyph?
    let symbolName: String
    let title: String
    let hue: AraHue?
    let isSelected: Bool
    /// The row whose filled shape slides between its chosen tabs; nil for a switch that
    /// fills on its own.
    let selection: Namespace.ID?
    let action: () -> Void
    @StateObject private var hover = AraHover()
    @Environment(\.araScale) private var ui

    var body: some View {
        Button {
            AraTooltipCenter.shared.hide()
            action()
        } label: {
            icon
                .foregroundStyle(
                    isSelected
                        ? AraPalette.onAccent(in: hue)
                        : (hue.map { AraPalette.tint($0).line } ?? AraPalette.ink).opacity(hover.isHovered ? 1 : 0.72))
                .frame(width: 30 * ui, height: 22 * ui)
                .background {
                    if isSelected, let selection {
                        Capsule().fill(AraPalette.accent(in: hue))
                            .matchedGeometryEffect(id: "tab", in: selection)
                    } else if isSelected {
                        Capsule().fill(AraPalette.accent(in: hue))
                    } else if hover.isHovered {
                        Capsule().fill(AraPalette.hoverWash)
                    }
                }
                .contentShape(Rectangle())
                .animation(AraTheme.hover, value: hover.isHovered)
        }
        .buttonStyle(AraPressStyle())
        .onHover { hover.isHovered = $0 }
        .araTooltip(title, isHovered: hover.isHovered)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var icon: some View {
        if let glyph {
            AraGlyphView(glyph, size: 15)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 12 * ui, weight: .semibold))
        }
    }
}
