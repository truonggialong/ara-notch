import NotchCore
import SwiftUI

public extension View {
    /// Fades a scrolling area at an end that has more beyond it, instead of cutting a card
    /// with a hard line (`ScrollEdges`). Put it on the `ScrollView`.
    func araScrollEdgeFade(_ axis: Axis = .vertical, length: CGFloat = 18) -> some View {
        modifier(AraScrollEdgeFade(axis: axis, length: length))
    }
}

struct AraScrollEdgeFade: ViewModifier {
    let axis: Axis
    let length: CGFloat
    @StateObject private var state = ScrollEdgeState()
    @Environment(\.araScale) private var ui

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: ScrollEdges.self) { geometry in
                axis == .vertical
                    ? ScrollEdges.of(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        visible: geometry.containerSize.height, content: geometry.contentSize.height)
                    : ScrollEdges.of(
                        offset: geometry.contentOffset.x + geometry.contentInsets.leading,
                        visible: geometry.containerSize.width, content: geometry.contentSize.width)
            } action: { _, new in
                withAnimation(.easeOut(duration: 0.15)) { state.edges = new }
            }
            .mask { mask }
    }

    @ViewBuilder
    private var mask: some View {
        let fade = length * ui
        let stack = Group {
            LinearGradient(colors: [.black.opacity(state.edges.start ? 0 : 1), .black], startPoint: start, endPoint: end)
                .frame(width: axis == .horizontal ? fade : nil, height: axis == .vertical ? fade : nil)
            Color.black
            LinearGradient(colors: [.black, .black.opacity(state.edges.end ? 0 : 1)], startPoint: start, endPoint: end)
                .frame(width: axis == .horizontal ? fade : nil, height: axis == .vertical ? fade : nil)
        }
        if axis == .vertical {
            VStack(spacing: 0) { stack }
        } else {
            HStack(spacing: 0) { stack }
        }
    }

    private var start: UnitPoint { axis == .vertical ? .top : .leading }
    private var end: UnitPoint { axis == .vertical ? .bottom : .trailing }
}

/// Which ends of one scrolling area fade now.
@MainActor
final class ScrollEdgeState: ObservableObject {
    @Published var edges = ScrollEdges(start: false, end: false)
}

/// Like items on a page that may be short (`RailLayout`): in rows of equal cells across the
/// width when they all fit, the last row centred; otherwise filling each column top to bottom
/// and scrolling sideways, never down, with its ends fading.
public struct AraRail<Item: Identifiable, Cell: View>: View {
    let items: [Item]
    let itemSize: CGSize
    let spacing: CGFloat
    let cell: (Item) -> Cell
    @Environment(\.araScale) private var ui

    /// - Parameter itemSize: the smallest a cell may be, before enlargement.
    public init(_ items: [Item], itemSize: CGSize, spacing: CGFloat = 8, @ViewBuilder cell: @escaping (Item) -> Cell) {
        self.items = items
        self.itemSize = itemSize
        self.spacing = spacing
        self.cell = cell
    }

    public var body: some View {
        GeometryReader { area in
            let item = CGSize(width: itemSize.width * ui, height: itemSize.height * ui)
            let gap = spacing * ui
            let plan = RailLayout.plan(count: items.count, item: item, spacing: gap, area: area.size)
            if plan.scrolls {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(item.height), spacing: gap), count: plan.rows), spacing: gap) {
                        ForEach(items) { cell($0).frame(width: item.width, height: item.height) }
                    }
                }
                .araScrollEdgeFade(.horizontal)
            } else if plan.columns > 0 {
                let width = (area.size.width - gap * CGFloat(plan.columns - 1)) / CGFloat(plan.columns)
                VStack(spacing: gap) {
                    ForEach(0..<plan.rows, id: \.self) { row in
                        HStack(spacing: gap) {
                            ForEach(items[row * plan.columns..<min((row + 1) * plan.columns, items.count)]) {
                                cell($0).frame(width: width, height: item.height)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

public extension View {
    /// Digits that do not jump: all as wide as each other, and rolling into the next reading,
    /// down while they count down and up while they count up. With Reduce Motion they change
    /// in place.
    func araRollingDigits<V: Equatable>(_ value: V, countsDown: Bool = true) -> some View {
        modifier(AraRollingDigits(value: value, countsDown: countsDown))
    }
}

struct AraRollingDigits<V: Equatable>: ViewModifier {
    let value: V
    let countsDown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: countsDown))
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: value)
    }
}
