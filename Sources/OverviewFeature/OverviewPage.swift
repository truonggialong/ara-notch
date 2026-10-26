import NotchCore
import NotchShell
import OverviewCore
import SwiftUI

/// The overview page: the features worth a glance, each on its own tile, on a grid of four
/// columns and two to four rows, in the order and sizes the user chose. In the edit mode the
/// tiles wobble, carry a button to remove them and one to change their size, and an "Add
/// tile" tile at the end offers the features not on the page.
struct OverviewPage: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var editor: OverviewEditor
    let tiles: [OverviewWidget: AnyView]
    /// Told how many rows the page has, so the notch can grow or shrink for them.
    let onRowsChange: (Int) -> Void

    var body: some View {
        let items = editor.shown
        let showsAdd = editor.isEditing && OverviewGrid.showsAddTile(items)
        let rows = editor.isEditing ? OverviewGrid.editingRows(items) : OverviewGrid.place(items).rows
        Group {
            if items.isEmpty, !editor.isEditing {
                VStack(spacing: 10 * ui) {
                    AraEmptyState(
                        icon: .grid, title: L10n.string("page.overview.empty.title"),
                        detail: L10n.string("page.overview.empty.detail"))
                    AraPillButton(L10n.string("overview.add"), icon: .add) {
                        editor.begin()
                        editor.isChoosingTile = true
                    }
                }
            } else {
                grid(items, rows: rows, showsAdd: showsAdd)
                    // The page's own margin is for pages with open ground; tiles go nearer the edge.
                    .padding(-OverviewGrid.gridOutset * ui)
                    .overlay(alignment: .bottom) {
                        if editor.isEditing, editor.isChoosingTile {
                            AddTileChooser(editor: editor)
                        }
                    }
            }
        }
        .onChange(of: rows, initial: true) { _, rows in onRowsChange(rows) }
    }

    private static let gridSpace = "overviewGrid"

    /// The tiles where the grid puts them. The rows share the height the page has, so a notch
    /// held short by the screen makes every row a little lower rather than cutting one off.
    /// A tile being dragged follows the pointer; the others make room for it as it goes.
    private func grid(_ items: [OverviewItem], rows: Int, showsAdd: Bool) -> some View {
        GeometryReader { proxy in
            let gap = OverviewGrid.gap * ui
            let columns = CGFloat(OverviewGrid.columns)
            let cell = CGSize(
                width: (proxy.size.width - (columns - 1) * gap) / columns,
                height: (proxy.size.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
            let step = CGSize(width: cell.width + gap, height: cell.height + gap)
            let placements = OverviewGrid.place(items).placements
            let dragged = editor.drag?.widget
            ZStack(alignment: .topLeading) {
                ForEach(placements, id: \.item.widget) { placement in
                    let isDragged = placement.item.widget == dragged
                    // The dragged tile stays where it was picked up, moved by the pointer.
                    let origin = isDragged ? startOrigin(of: placement.item.widget, step: step) ?? .zero : CGPoint(
                        x: CGFloat(placement.column) * step.width, y: CGFloat(placement.row) * step.height)
                    let size = frameSize(placement.item.size, cell: cell, gap: gap)
                    editableTile(placement.item, size: size, index: placement.column + placement.row * OverviewGrid.columns)
                        .offset(x: origin.x, y: origin.y)
                        .offset(isDragged ? editor.dragTranslation : .zero)
                        .zIndex(isDragged ? 1 : 0)
                        .shadow(color: .black.opacity(isDragged ? 0.35 : 0), radius: 10 * ui, y: 4 * ui)
                        .gesture(dragGesture(placement.item.widget, step: step, bounds: proxy.size), isEnabled: editor.isEditing)
                }
                if showsAdd, let add = OverviewGrid.place(items + [Self.addStandIn(items)]).placements.last {
                    AddTileButton(isChoosing: editor.isChoosingTile) { editor.isChoosingTile.toggle() }
                        .frame(width: cell.width, height: cell.height)
                        .offset(x: CGFloat(add.column) * step.width, y: CGFloat(add.row) * step.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .coordinateSpace(name: Self.gridSpace)
            .animation(AraTheme.settle, value: placements)
        }
    }

    private func frameSize(_ size: WidgetSize, cell: CGSize, gap: CGFloat) -> CGSize {
        CGSize(
            width: CGFloat(size.columns) * cell.width + CGFloat(size.columns - 1) * gap,
            height: CGFloat(size.rows) * cell.height + CGFloat(size.rows - 1) * gap)
    }

    /// Where a tile stood when the drag began.
    private func startOrigin(of widget: OverviewWidget, step: CGSize) -> CGPoint? {
        guard let start = editor.drag?.start,
              let placement = OverviewGrid.place(start).placements.first(where: { $0.item.widget == widget })
        else { return nil }
        return CGPoint(x: CGFloat(placement.column) * step.width, y: CGFloat(placement.row) * step.height)
    }

    /// Picks a tile up and carries it; the cell under the pointer says where it would land.
    /// Let go on the page and the new order is kept; off the page, the tile goes back.
    private func dragGesture(_ widget: OverviewWidget, step: CGSize, bounds: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.gridSpace))
            .onChanged { value in
                // Whole cells the tile's own corner has travelled, wherever it was grabbed.
                editor.dragTile(
                    widget,
                    byColumns: Int((value.translation.width / step.width).rounded()),
                    rows: Int((value.translation.height / step.height).rounded()),
                    translation: value.translation,
                    isOnGrid: CGRect(origin: .zero, size: bounds).contains(value.location))
            }
            .onEnded { value in
                editor.dropTile(inside: CGRect(origin: .zero, size: bounds).contains(value.location))
            }
    }

    /// A small tile of a feature not on the page, standing for the add tile when placing.
    private static func addStandIn(_ items: [OverviewItem]) -> OverviewItem {
        let widget = OverviewWidget.allCases.first { OverviewGrid.adding(items, widget: $0) != nil } ?? .media
        return OverviewItem(widget: widget, size: .small)
    }

    private func editableTile(_ item: OverviewItem, size: CGSize, index: Int) -> some View {
        tile(item.widget)
            .environment(\.araTileSize, item.size)
            // While the tiles are arranged their content does nothing: no paste, no pause.
            .allowsHitTesting(!editor.isEditing)
            // Its place first, then the clip: a tile never spills out of its cell into its
            // neighbours, whatever it holds.
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 14 * ui, style: .continuous))
            // The whole tile still takes the pointer, so it can be picked up and dragged.
            .contentShape(RoundedRectangle(cornerRadius: 14 * ui, style: .continuous))
            .modifier(Wobble(isOn: editor.isEditing, phase: index))
            .overlay(alignment: .topLeading) {
                if editor.isEditing {
                    // On the corner, half outside the tile, so the tile's name stays readable.
                    AraIconButton(.remove, look: .danger, size: .small, help: L10n.string("overview.remove")) {
                        editor.remove(item.widget)
                    }
                    .scaleEffect(0.8)
                    .offset(x: -7 * ui, y: -7 * ui)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Only a kind with more than one size has a size button; it says which way
                // the next size goes, larger or back to the smallest. On the corner, half
                // outside the tile like the remove button, so the widget's figures stay in sight.
                let sizes = item.widget.sizes
                if editor.isEditing, sizes.count > 1 {
                    let next = sizes[((sizes.firstIndex(of: item.size) ?? 0) + 1) % sizes.count]
                    AraIconButton(
                        next == sizes[0] ? .shrink : .enlarge, size: .small, help: L10n.string("overview.resize")
                    ) {
                        editor.resize(item.widget)
                    }
                    .scaleEffect(0.8)
                    .offset(x: 7 * ui, y: 7 * ui)
                }
            }
            .overlay {
                if editor.refusedWidget == item.widget {
                    Text(L10n.string("overview.noRoom"))
                        .font(.system(size: 10.5 * ui, weight: .semibold))
                        .padding(.horizontal, 10 * ui)
                        .padding(.vertical, 4 * ui)
                        .araSurface(Capsule())
                        .transition(.opacity)
                }
            }
            .modifier(Shake(times: CGFloat(editor.refusals[item.widget] ?? 0)))
            .animation(.easeInOut(duration: 0.3), value: editor.refusals[item.widget])
            .animation(.easeInOut(duration: 0.3), value: editor.refusedWidget)
            .contextMenu {
                if !editor.isEditing {
                    Button(L10n.string("overview.edit")) { editor.begin() }
                }
            }
    }

    /// The feature's own tile; one that has none yet keeps its place with its name.
    @ViewBuilder
    private func tile(_ widget: OverviewWidget) -> some View {
        if let tile = tiles[widget] {
            tile
        } else {
            AraWidget(name: widget.title, hue: widget.hue) {
                AraWidgetHeader(label: widget.title)
            }
        }
    }
}

/// The pencil on the tab row while the overview shows; Done while it is edited.
struct OverviewEditButton: View {
    @ObservedObject var editor: OverviewEditor

    var body: some View {
        NotchToolbarButton(
            symbolName: editor.isEditing ? "checkmark" : AraIcon.edit.symbolName,
            title: L10n.string(editor.isEditing ? "overview.done" : "overview.edit"),
            isOn: editor.isEditing
        ) {
            editor.isEditing ? editor.end() : editor.begin()
        }
    }
}

/// The last place on the grid while editing: a dashed outline with a plus.
private struct AddTileButton: View {
    @Environment(\.araScale) private var ui
    let isChoosing: Bool
    let action: () -> Void
    @StateObject private var hover = AraHover()

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3 * ui) {
                AraIcon.add.image
                    .font(.system(size: 13 * ui, weight: .semibold))
                Text(L10n.string("overview.add"))
                    .font(.system(size: 10 * ui, weight: .medium))
            }
            .foregroundStyle(AraTheme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14 * ui, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2 * ui, dash: [4 * ui, 3 * ui]))
                    .foregroundStyle(AraTheme.secondaryText.opacity(isChoosing || hover.isHovered ? 0.9 : 0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
        .onHover { hover.isHovered = $0 }
    }
}

/// The features not on the page, as chips in their pages' colours; a click adds one, small,
/// at the end.
private struct AddTileChooser: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var editor: OverviewEditor

    var body: some View {
        let widgets = editor.addableWidgets
        // One chip for each feature not on the page; wraps onto more lines.
        AraFlowRow(spacing: 6 * ui) {
            ForEach(widgets, id: \.self) { widget in
                AraChip {
                    editor.add(widget)
                } label: {
                    Label(widget.title, systemImage: widget.icon.symbolName)
                        .font(.system(size: 10.5 * ui, weight: .medium))
                        .lineLimit(1)
                }
                .araHue(widget.hue)
            }
        }
        .padding(6 * ui)
        .araSurface(RoundedRectangle(cornerRadius: 14 * ui, style: .continuous))
        .padding(.bottom, 2 * ui)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Tiles being arranged turn a little to and fro, each a little out of step with the others.
private struct Wobble: ViewModifier {
    let isOn: Bool
    let phase: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // An object rather than @State: the build tools on this Mac cannot expand @State.
    @StateObject private var tilt = WobbleTilt()

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isOn && !reduceMotion ? (tilt.isTilted ? 0.8 : -0.8) : 0))
            .onChange(of: isOn, initial: true) { _, isOn in
                guard isOn, !reduceMotion else {
                    tilt.isTilted = false
                    return
                }
                withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true).delay(Double(phase % 3) * 0.04)) {
                    tilt.isTilted.toggle()
                }
            }
    }
}

private final class WobbleTilt: ObservableObject {
    @Published var isTilted = false
}

/// A side-to-side shake, for a tile whose size cannot change.
private struct Shake: GeometryEffect {
    var times: CGFloat

    var animatableData: CGFloat {
        get { times }
        set { times = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(times * .pi * 4), y: 0))
    }
}

extension OverviewWidget {
    var title: String {
        L10n.string("overview.tile.\(rawValue)")
    }

    /// The feature's symbol.
    var icon: AraIcon {
        switch feature {
        case .media: return .music
        case .calendar: return .calendar
        case .timer: return .timer
        case .clipboard: return .clipboard
        case .tools: return .grid
        case .agents: return .agents
        case .device: return .output
        }
    }

    /// The colour of the feature's page.
    var hue: AraHue? {
        switch feature {
        case .media: return .sky
        case .calendar: return .mustard
        case .timer: return .mint
        case .clipboard: return .peach
        case .tools: return nil
        case .agents: return .lilac
        case .device: return .sage
        }
    }
}
