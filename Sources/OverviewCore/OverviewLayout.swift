import Foundation
import NotchCore

/// The feature a tile of the overview belongs to. The order is the order of the "Add tile" chips.
public enum OverviewTileGroup: String, CaseIterable, Sendable {
    case media, calendar, timer, clipboard, agents, device, tools
}

/// A kind of tile of the overview page: one widget for each feature, in every size. Small
/// already says what matters; wide says it in more detail; large in more detail and for more
/// things.
public enum OverviewWidget: String, CaseIterable, Sendable {
    case media, calendar, timer, clipboard, tools, agents, device

    public var feature: OverviewTileGroup {
        switch self {
        case .media: .media
        case .calendar: .calendar
        case .timer: .timer
        case .clipboard: .clipboard
        case .agents: .agents
        case .device: .device
        case .tools: .tools
        }
    }

    /// The sizes this kind may have, smallest first.
    public var sizes: [WidgetSize] {
        [.small, .wide, .large]
    }
}

/// One tile of the overview as the user arranged it.
public struct OverviewItem: Equatable, Sendable {
    public var widget: OverviewWidget
    public var size: WidgetSize

    public init(widget: OverviewWidget, size: WidgetSize) {
        self.widget = widget
        self.size = size
    }
}

/// Where a tile stands on the grid: the cell of its top left corner.
public struct OverviewPlacement: Equatable, Sendable {
    public let item: OverviewItem
    public let column: Int
    public let row: Int
}

/// The overview's grid: four columns, as many rows as the tiles need, from two to four.
/// Tiles go in their order, each into the first gap it fits, left to right and top to
/// bottom, so a small tile after a wide one fills the hole the wide one left.
public enum OverviewGrid {
    public static let columns = 4
    public static let minimumRows = 2
    public static let maximumRows = 4

    /// Two full rows, as tall as the overview always was. The quick tools are left out: they
    /// have a page of their own.
    public static let defaultArrangement: [OverviewItem] = [
        OverviewItem(widget: .media, size: .wide), OverviewItem(widget: .calendar, size: .wide),
        OverviewItem(widget: .timer, size: .small), OverviewItem(widget: .agents, size: .small),
        OverviewItem(widget: .clipboard, size: .small), OverviewItem(widget: .device, size: .small),
    ]

    /// Where each tile stands and how many rows the page needs (never fewer than two).
    /// More than four rows are counted, so a caller can tell the tiles do not fit.
    public static func place(_ items: [OverviewItem]) -> (placements: [OverviewPlacement], rows: Int) {
        var taken: [[Bool]] = []
        var placements: [OverviewPlacement] = []
        for item in items {
            let width = item.size.columns, height = item.size.rows
            var row = 0
            search: while true {
                while taken.count < row + height {
                    taken.append(Array(repeating: false, count: columns))
                }
                for column in 0...(columns - width) {
                    let cells = (row..<row + height).flatMap { r in (column..<column + width).map { (r, $0) } }
                    if cells.allSatisfy({ !taken[$0.0][$0.1] }) {
                        cells.forEach { taken[$0.0][$0.1] = true }
                        placements.append(OverviewPlacement(item: item, column: column, row: row))
                        break search
                    }
                }
                row += 1
            }
        }
        let used = (taken.lastIndex { $0.contains(true) } ?? -1) + 1
        return (placements, max(minimumRows, used))
    }

    /// An arrangement read from `"<widget>:<size>"` entries; an earlier kind's name reads as
    /// its feature's widget. Entries that are no tile, a feature a second time, and tiles past
    /// the fourth row are dropped.
    public static func arrangement(from entries: [String]) -> [OverviewItem] {
        var items: [OverviewItem] = []
        for entry in entries {
            let parts = entry.split(separator: ":").map(String.init)
            guard parts.count == 2, let widget = widget(named: parts[0]),
                let size = WidgetSize(rawValue: parts[1]),
                !items.contains(where: { $0.widget == widget })
            else { continue }
            // A size the kind does not have becomes its smallest, so the tile is kept.
            items.append(OverviewItem(widget: widget, size: widget.sizes.contains(size) ? size : widget.sizes[0]))
        }
        while !fits(items) {
            items.removeLast()
        }
        return items
    }

    /// The visual kinds of 0.26.0, kept by name so a saved page keeps its tiles: each became
    /// its feature's widget.
    private static let legacyKinds: [String: OverviewWidget] = [
        "albumArt": .media, "dayClock": .calendar, "timerDisc": .timer, "clipStack": .clipboard,
        "colorPalette": .clipboard, "usageRings": .agents, "deviceRings": .device,
    ]

    /// The kind a saved name stands for, the names of earlier kinds included; nil for none.
    private static func widget(named name: String) -> OverviewWidget? {
        if name.hasPrefix("tool."), name.count > "tool.".count { return .tools }
        return legacyKinds[name] ?? OverviewWidget(rawValue: name)
    }

    public static func entries(of items: [OverviewItem]) -> [String] {
        items.map { "\($0.widget.rawValue):\($0.size.rawValue)" }
    }

    /// Whether the tiles fit in the most rows the page may have.
    public static func fits(_ items: [OverviewItem]) -> Bool {
        place(items).rows <= maximumRows
    }

    /// The tile at its next size that still fits: small, wide, large, around again. Nil when
    /// the tile is not on the page or no other size fits.
    public static func resized(_ items: [OverviewItem], widget: OverviewWidget) -> [OverviewItem]? {
        guard let index = items.firstIndex(where: { $0.widget == widget }) else { return nil }
        let sizes = widget.sizes
        let current = items[index].size
        let start = sizes.firstIndex(of: current) ?? 0
        // The kind's sizes around from the one after the current: small, then larger, then small again.
        for step in 1..<max(sizes.count, 1) {
            var changed = items
            changed[index].size = sizes[(start + step) % sizes.count]
            if fits(changed) { return changed }
        }
        return nil
    }

    /// The tile taken out and put back at `index`, kept within the list.
    public static func moved(_ items: [OverviewItem], widget: OverviewWidget, to index: Int) -> [OverviewItem] {
        guard let from = items.firstIndex(where: { $0.widget == widget }) else { return items }
        var changed = items
        let tile = changed.remove(at: from)
        changed.insert(tile, at: min(max(index, 0), changed.count))
        return changed
    }

    /// The tile added at the end in its smallest size. Nil when it is already there or there
    /// is no room.
    public static func adding(_ items: [OverviewItem], widget: OverviewWidget) -> [OverviewItem]? {
        guard !items.contains(where: { $0.widget == widget }) else { return nil }
        let changed = items + [OverviewItem(widget: widget, size: widget.sizes[0])]
        return fits(changed) ? changed : nil
    }

    public static func removing(_ items: [OverviewItem], widget: OverviewWidget) -> [OverviewItem] {
        items.filter { $0.widget != widget }
    }

    /// Whether the edit mode shows the "Add tile" tile: a feature is not on the page yet and
    /// a small tile still fits.
    public static func showsAddTile(_ items: [OverviewItem]) -> Bool {
        OverviewWidget.allCases.contains { adding(items, widget: $0) != nil }
    }

    /// The rows the page has while it is edited: the "Add tile" tile takes a small place at
    /// the end and may need a row of its own.
    public static func editingRows(_ items: [OverviewItem]) -> Int {
        guard showsAddTile(items) else { return place(items).rows }
        // Any missing feature stands in for the add tile: it is small and goes last.
        let stand = OverviewWidget.allCases.first { adding(items, widget: $0) != nil } ?? .media
        return place(items + [OverviewItem(widget: stand, size: .small)]).rows
    }

    /// Where in the list the tile covering this cell is; nil for an empty cell.
    public static func index(atColumn column: Int, row: Int, in items: [OverviewItem]) -> Int? {
        place(items).placements.firstIndex { placement in
            (placement.column..<placement.column + placement.item.size.columns).contains(column)
                && (placement.row..<placement.row + placement.item.size.rows).contains(row)
        }
    }

    /// Where in the list a dragged tile lands when let go over this cell: the place of the
    /// tile under the pointer, laid out without the dragged one; past the end over an empty cell.
    public static func dropIndex(column: Int, row: Int, dragging widget: OverviewWidget, in items: [OverviewItem]) -> Int {
        let others = removing(items, widget: widget)
        return index(atColumn: column, row: row, in: others) ?? others.count
    }

    /// The room between two tiles, on the sheet before enlargement.
    public static let gap: CGFloat = 6
    /// How far the grid reaches past the page's own margin on every side.
    public static let gridOutset: CGFloat = 4

    /// The sheet the page asks the notch for; nil for two rows, the usual sheet. `chrome` is
    /// what of the open notch holds no tile, in sheet points: the tab row and the page's
    /// margins. The tab row keeps the hardware notch's height while the page is enlarged, so
    /// this differs between sizes; with it, every row added is exactly as tall as the two
    /// rows the usual sheet has.
    public static func sheetHeight(rows: Int, chrome: CGFloat) -> CGFloat? {
        guard rows > minimumRows else { return nil }
        let usual = NotchGeometry.defaultOpenSize.height
        let usualRow = (usual - chrome + 2 * gridOutset - gap) / CGFloat(minimumRows)
        return usual + CGFloat(rows - minimumRows) * (usualRow + gap)
    }
}

/// The overview as a page among the others.
public enum OverviewLayout {
    public static let pageID = "overview"
}

/// A tile being dragged to a new place on the overview. The page shows `preview` while the
/// drag goes on; nothing is kept until it is dropped on the grid with a new order.
public struct OverviewDrag: Equatable, Sendable {
    public let widget: OverviewWidget
    /// The arrangement when the drag began; every move is measured against it.
    public let start: [OverviewItem]
    public private(set) var preview: [OverviewItem]

    public init(widget: OverviewWidget, from items: [OverviewItem]) {
        self.widget = widget
        start = items
        preview = items
    }

    /// The pointer is over this cell of the grid.
    public mutating func move(toColumn column: Int, row: Int) {
        let index = OverviewGrid.dropIndex(column: column, row: row, dragging: widget, in: start)
        preview = OverviewGrid.moved(start, widget: widget, to: index)
    }

    /// The tile has been carried this many whole cells from where it stood. Where it lands
    /// follows its top left corner, not the cell under the pointer, so a wide or large tile
    /// picked up by any of its cells stays put until it is really moved.
    public mutating func move(byColumns columns: Int, rows: Int) {
        guard let origin = OverviewGrid.place(start).placements.first(where: { $0.item.widget == widget }) else { return }
        let size = origin.item.size
        let column = min(max(origin.column + columns, 0), OverviewGrid.columns - size.columns)
        let row = min(max(origin.row + rows, 0), OverviewGrid.maximumRows - size.rows)
        if column == origin.column, row == origin.row {
            preview = start
        } else {
            move(toColumn: column, row: row)
        }
    }

    /// The pointer has left the grid: let go there, the tile goes back, so the others show
    /// the order it started from.
    public mutating func moveOffGrid() {
        preview = start
    }

    /// The arrangement to keep: nil when let go off the grid or when nothing moved.
    public func drop(inside: Bool) -> [OverviewItem]? {
        inside && preview != start ? preview : nil
    }
}
