import AppKit
import NotchCore
import SwiftUI

// MARK: - Where a view is drawn

private struct AraOnNotchKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True for what is drawn on the open notch. Cards there are white of a few strengths over
    /// black or glass, rather than a grey of their own, so the glass shows through them.
    var araOnNotch: Bool {
        get { self[AraOnNotchKey.self] }
        set { self[AraOnNotchKey.self] = newValue }
    }
}

/// The strengths of white the notch's surfaces are drawn with, on black or glass.
public enum AraNotchWhite {
    /// A resting card.
    public static let card = 0.065
    /// A card or button under the pointer.
    public static let hover = 0.09
    /// A chosen or switched-on plate.
    public static let selected = 0.13
    /// A well: a quiet field, an empty track.
    public static let well = 0.05
}

public extension AraPalette {
    /// A well (a quiet button, a field, a bar of tools): on the notch, a faint white over
    /// black or glass; elsewhere the theme's own well.
    static func well(onNotch: Bool) -> Color {
        onNotch ? Color.white.opacity(AraNotchWhite.card + 0.015) : well
    }
}

// MARK: - What the open notch is laid on

/// Black, dark glass or Liquid Glass. Whatever the material, the strip beside the camera
/// stays black, so the hardware notch never shows as a hole in the glass.
struct NotchBackdrop: View {
    let material: NotchMaterial
    let bandHeight: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shown = material.shown(reduceTransparency: reduceTransparency)
        switch shown {
        case .black:
            AraNotchGround()
        case .glass, .liquid:
            let shade = shown.shade(increasedContrast: contrast == .increased)
            ZStack(alignment: .top) {
                glass(shown)
                VStack(spacing: 0) {
                    Color.black.frame(height: bandHeight)
                    LinearGradient(colors: [.black, .black.opacity(shade)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                    Color.black.opacity(shade)
                }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func glass(_ material: NotchMaterial) -> some View {
        if material == .liquid, #available(macOS 26, *) {
            Color.clear.glassEffect(.clear, in: Rectangle())
        } else {
            NotchBlur()
        }
    }
}

/// The system's blur of what is behind the window.
private struct NotchBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Round buttons around the open notch

/// The round buttons that stand around the open notch. As it opens they pour out of its edge
/// one after another, each joined to the notch by a neck of ink that parts just before the
/// button stops; as it closes they are gone at once.
struct NotchOrbits: View {
    @ObservedObject var model: NotchViewModel
    @StateObject private var reveal = OrbitReveal()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stagger = 0.06
    private static let travel = 0.42
    private static let delay = 0.12

    var body: some View {
        let scale = model.edgeScale
        let slots = OrbitSlot.allCases.filter { model.orbit.actions[$0] != nil }
        let gutter = (OrbitLayout.gutter + NotchMotion.overshootRoom) * scale
        let size = CGSize(width: model.openSize.width + 2 * gutter, height: model.openSize.height + gutter)
        ZStack(alignment: .topLeading) {
            if reveal.isPouring, !reduceMotion {
                TimelineView(.animation(paused: false)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(reveal.start)
                    Canvas { context, _ in
                        context.addFilter(.alphaThreshold(min: 0.5, color: .black))
                        context.addFilter(.blur(radius: 7 * scale))
                        context.drawLayer { layer in
                            for (index, slot) in slots.enumerated() {
                                let progress = Self.progress(index: index, elapsed: elapsed)
                                guard progress > 0 else { continue }
                                let target = centre(slot, gutter: gutter, scale: scale)
                                let anchor = self.anchor(slot, gutter: gutter, scale: scale)
                                let eased = Self.backOut(progress)
                                let point = CGPoint(x: anchor.x + (target.x - anchor.x) * eased, y: anchor.y + (target.y - anchor.y) * eased)
                                let radius = OrbitLayout.diameter * scale / 2
                                layer.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(.black))
                                // The ink left at the notch's edge shrinks away: the neck between it and the button parts.
                                let left = radius * max(0, 1 - progress / 0.62)
                                if left > 0 {
                                    layer.fill(Path(ellipseIn: CGRect(x: anchor.x - left, y: anchor.y - left, width: 2 * left, height: 2 * left)), with: .color(.black))
                                }
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .onChange(of: elapsed > Self.totalTime(count: slots.count)) { _, done in
                        if done { reveal.finish() }
                    }
                }
                .allowsHitTesting(false)
            }
            ForEach(slots, id: \.self) { slot in
                if let action = model.orbit.actions[slot] {
                    let point = centre(slot, gutter: gutter, scale: scale)
                    OrbitButton(model: model, action: action, scale: scale, solid: !reveal.isPouring || reduceMotion)
                        .position(x: point.x, y: point.y)
                        .opacity(reveal.shows ? 1 : 0)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .offset(x: -gutter)
        .opacity(model.isOpen ? 1 : 0)
        .animation(model.isOpen ? .easeOut(duration: 0.2) : .easeIn(duration: 0.12), value: model.isOpen)
        .allowsHitTesting(model.isOpen)
        .onChange(of: model.isOpen) { _, isOpen in
            reveal.begin(isOpen, after: Self.delay)
        }
    }

    private func centre(_ slot: OrbitSlot, gutter: CGFloat, scale: CGFloat) -> CGPoint {
        let point = OrbitLayout.centre(of: slot, openSize: model.openSize, scale: scale)
        return CGPoint(x: point.x + gutter, y: point.y)
    }

    /// Where a button pours out from: the point of the notch's edge nearest to it.
    private func anchor(_ slot: OrbitSlot, gutter: CGFloat, scale: CGFloat) -> CGPoint {
        let target = centre(slot, gutter: gutter, scale: scale)
        switch slot.side {
        case .left: return CGPoint(x: gutter + 4 * scale, y: target.y)
        case .right: return CGPoint(x: gutter + model.openSize.width - 4 * scale, y: target.y)
        case .bottom: return CGPoint(x: target.x, y: model.openSize.height - 4 * scale)
        }
    }

    static func progress(index: Int, elapsed: TimeInterval) -> Double {
        min(max((elapsed - Double(index) * stagger) / travel, 0), 1)
    }

    static func totalTime(count: Int) -> TimeInterval {
        Double(max(count - 1, 0)) * stagger + travel
    }

    /// Eases out past the end and settles back.
    static func backOut(_ t: Double) -> Double {
        let c1 = 1.2, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

/// Whether the buttons are pouring out now, and since when.
@MainActor
final class OrbitReveal: ObservableObject {
    @Published private(set) var isPouring = false
    @Published private(set) var shows = false
    private(set) var start = Date()
    private var pending: DispatchWorkItem?

    func begin(_ isOpen: Bool, after delay: TimeInterval) {
        pending?.cancel()
        guard isOpen else {
            isPouring = false
            shows = false
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.start = Date()
            self.isPouring = true
            // The buttons themselves come once their ink has nearly arrived.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.shows = true }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func finish() {
        isPouring = false
        shows = true
    }
}

/// One round button beside the open notch.
private struct OrbitButton: View {
    @ObservedObject var model: NotchViewModel
    let action: OrbitAction
    let scale: CGFloat
    /// Drawn as a black disc of its own once its ink has stopped flowing.
    let solid: Bool
    @StateObject private var hover = AraHover()

    var body: some View {
        let diameter = OrbitLayout.diameter * scale
        Button {
            AraTooltipCenter.shared.hide()
            model.onOrbit?(action)
        } label: {
            icon
                .foregroundStyle(tint)
                .frame(width: diameter, height: diameter)
                .background {
                    Circle().fill(Color.black.opacity(solid ? 1 : 0))
                        .overlay(Circle().fill(Color.white.opacity(hover.isHovered || isOn ? AraNotchWhite.hover : 0)))
                        .overlay(Circle().strokeBorder(Color.white.opacity(isOn ? 0.6 : 0.16), lineWidth: 0.75))
                }
                .contentShape(Circle())
                .scaleEffect(hover.isHovered ? 1.04 : 1)
                .animation(AraTheme.hover, value: hover.isHovered)
        }
        .buttonStyle(AraPressStyle(depth: 0.94))
        .onHover { hover.isHovered = $0 }
        .araTooltip(title, isHovered: hover.isHovered)
        .accessibilityLabel(title)
    }

    private var isOn: Bool {
        switch action {
        case .explore: model.isExploring
        case .pin: model.isPinned
        case let .page(id): !model.isExploring && model.registry.selectedID == id
        case .settings: false
        }
    }

    private var descriptor: PageDescriptor? {
        if case let .page(id) = action {
            return model.registry.allPages.first { $0.id == id }
        }
        return nil
    }

    private var title: String {
        switch action {
        case .explore: L10n.string(model.isExploring ? "notch.explore.back" : "notch.explore")
        case .settings: L10n.string("notch.settings.tooltip")
        case .pin: L10n.string(model.isPinned ? "notch.pin.on" : "notch.pin.off")
        case let .page(id): descriptor.map { L10n.string($0.titleKey) } ?? id
        }
    }

    private var tint: Color {
        if case let .page(id) = action, let hue = model.pages[id]?.hue {
            return AraPalette.tint(hue).line
        }
        return AraPalette.ink.opacity(0.92)
    }

    @ViewBuilder
    private var icon: some View {
        switch action {
        case .explore:
            Image(systemName: model.isExploring ? "arrow.uturn.backward" : "square.grid.2x2")
                .font(.system(size: 16 * scale, weight: .medium))
        case .settings:
            AraGlyphView(.settings, size: 16)
                .environment(\.araScale, scale)
        case .pin:
            Image(systemName: model.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 15 * scale, weight: .medium))
        case let .page(id):
            if let glyph = AraGlyph(pageID: id) {
                AraGlyphView(glyph, size: 17)
                    .environment(\.araScale, scale)
            } else {
                Image(systemName: descriptor?.symbolName ?? "square")
                    .font(.system(size: 16 * scale, weight: .medium))
            }
        }
    }
}

// MARK: - Every page at a glance

/// Every page as a tile, with the key that opens it, and below them, when several things are
/// going on, which of them shows beside the closed notch.
struct NotchExploreGrid: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.araScale) private var ui

    static let columns = 5

    var body: some View {
        let letters = model.exploreLetters
        VStack(alignment: .leading, spacing: 10 * ui) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6 * ui), count: Self.columns), spacing: 6 * ui
            ) {
                ForEach(model.registry.pages) { page in
                    ExploreTile(
                        model: model, descriptor: page, letter: letters[page.id],
                        isCurrent: page.id == model.registry.selectedID)
                }
            }
            if model.restingOptions.count >= 2 {
                RestingChooser(model: model)
            }
            Spacer(minLength: 0)
        }
    }

    /// The sheet the grid needs for this many pages, before enlargement.
    static func sheet(pages: Int, chooser: Bool) -> CGSize {
        let rows = max(1, Int((Double(pages) / Double(columns)).rounded(.up)))
        let height = 26 + Double(rows) * 58 + Double(rows - 1) * 6 + 4 + 14 + (chooser ? 40 : 0)
        return CGSize(width: 380, height: height)
    }
}

private struct ExploreTile: View {
    @ObservedObject var model: NotchViewModel
    let descriptor: PageDescriptor
    let letter: Character?
    let isCurrent: Bool
    @StateObject private var hover = AraHover()
    @Environment(\.araScale) private var ui

    var body: some View {
        let hue = model.pages[descriptor.id]?.hue
        Button {
            model.onSelectPage?(descriptor.id)
        } label: {
            VStack(spacing: 3 * ui) {
                Group {
                    if let glyph = AraGlyph(pageID: descriptor.id) {
                        AraGlyphView(glyph, size: 17)
                    } else {
                        Image(systemName: descriptor.symbolName).font(.system(size: 15 * ui, weight: .medium))
                    }
                }
                .foregroundStyle(hue.map { AraPalette.tint($0).line } ?? AraPalette.ink.opacity(0.85))
                .frame(height: 20 * ui)
                Text(L10n.string(descriptor.titleKey))
                    .font(.system(size: 10.5 * ui, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let letter {
                    Text("⌥⌘\(String(letter))")
                        .font(.system(size: 9 * ui, weight: .medium, design: .rounded))
                        .foregroundStyle(AraPalette.ink.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58 * ui)
            .background {
                RoundedRectangle(cornerRadius: 14 * ui, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? AraNotchWhite.selected : (hover.isHovered ? AraNotchWhite.hover : 0.045)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14 * ui, style: .continuous)
                            .strokeBorder(Color.white.opacity(isCurrent ? 0.5 : 0.04), lineWidth: 1))
            }
            .overlay(alignment: .topTrailing) {
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9 * ui))
                        .foregroundStyle(AraPalette.ink.opacity(0.7))
                        .padding(5 * ui)
                }
            }
            .contentShape(Rectangle())
            .scaleEffect(hover.isHovered ? 1.022 : 1)
            .animation(AraTheme.hover, value: hover.isHovered)
        }
        .buttonStyle(AraPressStyle(depth: 0.965))
        .onHover { hover.isHovered = $0 }
        .accessibilityLabel(L10n.string(descriptor.titleKey))
    }
}

/// Which of the things going on now shows beside the closed notch: one, two together, or
/// whichever matters most.
private struct RestingChooser: View {
    @ObservedObject var model: NotchViewModel
    @Environment(\.araScale) private var ui

    var body: some View {
        let options = model.restingOptions
        let shown = model.restingChoice.shown(Dictionary(uniqueKeysWithValues: options.enumerated().map { ($1.id, options.count - $0) }))
        VStack(alignment: .leading, spacing: 5 * ui) {
            Text(L10n.string("notch.resting.title"))
                .font(.system(size: 9.5 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.ink.opacity(0.5))
            HStack(spacing: 6 * ui) {
                chip(L10n.string("notch.resting.auto"), symbol: "sparkles", isOn: model.restingChoice.preferred == nil) {
                    model.onChooseResting?(nil)
                }
                ForEach(options) { option in
                    chip(option.title, symbol: option.symbolName, isOn: model.restingChoice.preferred == .one(option.id)) {
                        model.onChooseResting?(.one(option.id))
                    }
                }
                if options.count >= 2 {
                    let pair = RestingSelection.Choice.pair(primary: options[0].id, companion: options[1].id)
                    chip(
                        L10n.string("notch.resting.both"),
                        symbol: "rectangle.split.2x1", isOn: model.restingChoice.preferred == pair
                    ) {
                        model.onChooseResting?(pair)
                    }
                }
            }
        }
        .accessibilityValue(shown.map { "\($0)" } ?? "")
    }

    private func chip(_ title: String, symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4 * ui) {
                Image(systemName: symbol).font(.system(size: 9 * ui, weight: .semibold))
                Text(title).font(.system(size: 11 * ui, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 9 * ui)
            .frame(height: 24 * ui)
            .foregroundStyle(isOn ? Color.black : AraPalette.ink)
            .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(AraNotchWhite.card)))
            .contentShape(Capsule())
        }
        .buttonStyle(AraPressStyle(depth: 0.965))
    }
}
