import Foundation
import Testing
import NotchCore
@testable import OverviewCore

@Suite struct OverviewLayoutTests {
    @Test func theDefaultFillsTwoRows() {
        let items = [
            item(.media, .wide), item(.calendar, .wide), item(.timer, .small),
            item(.agents, .small), item(.clipboard, .small), item(.device, .small),
        ]
        let result = OverviewGrid.place(items)
        #expect(result.rows == 2)
        #expect(result.placements.map { [$0.column, $0.row] } == [[0, 0], [2, 0], [0, 1], [1, 1], [2, 1], [3, 1]])
    }

    @Test func aSmallTileFillsTheGapAWideOneLeaves() {
        // The second wide tile does not fit in the one column left on row 0, so it starts row 1;
        // the small tile after it goes back up into that column.
        let result = OverviewGrid.place([item(.timer, .small), item(.media, .wide), item(.calendar, .wide), item(.agents, .small)])
        #expect(result.placements.map { [$0.column, $0.row] } == [[0, 0], [1, 0], [0, 1], [3, 0]])
    }

    @Test func aLargeTileTakesTwoRows() {
        let result = OverviewGrid.place([item(.media, .large), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)])
        #expect(result.placements.map { [$0.column, $0.row] } == [[0, 0], [2, 0], [2, 1], [3, 1]])
        #expect(result.rows == 2)
    }

    @Test func thePageNeverHasFewerThanTwoRows() {
        #expect(OverviewGrid.place([]).rows == 2)
        #expect(OverviewGrid.place([item(.timer, .small)]).rows == 2)
    }

    @Test func moreThanFourRowsDoesNotFit() {
        let four = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .large)]
        #expect(OverviewGrid.fits(four))
        #expect(OverviewGrid.place(four).rows == 4)
        #expect(!OverviewGrid.fits(four + [item(.device, .small)]))
    }

    @Test func resizingTakesTheNextSizeThatFits() {
        let full = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .wide), item(.device, .small)]
        // Agents wide to large would need a fifth row; it goes on to small instead.
        #expect(OverviewGrid.resized(full, widget: .agents)?.first { $0.widget == .agents }?.size == .small)
        // Device small to wide fits beside agents on the last row.
        #expect(OverviewGrid.resized(full, widget: .device)?.first { $0.widget == .device }?.size == .wide)
    }

    @Test func resizingWithNoOtherSizeThatFitsGivesNil() {
        // Sixteen cells taken: a small tile can neither widen nor grow.
        let full = [
            item(.media, .large), item(.calendar, .large), item(.timer, .large),
            item(.agents, .wide), item(.device, .small), item(.tools, .small),
        ]
        #expect(OverviewGrid.resized(full, widget: .tools) == nil)
        // A tile that is not on the page has nothing to resize.
        #expect(OverviewGrid.resized([item(.media, .small)], widget: .tools) == nil)
    }

    @Test func movingPutsATileAtAnIndex() {
        let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small)]
        #expect(OverviewGrid.moved(items, widget: .timer, to: 0).map(\.widget) == [.timer, .media, .calendar])
        #expect(OverviewGrid.moved(items, widget: .media, to: 9).map(\.widget) == [.calendar, .timer, .media])
    }

    @Test func addingIsSmallAtTheEndOnceAndOnlyWithRoom() {
        let items = [item(.media, .wide)]
        #expect(OverviewGrid.adding(items, widget: .tools) == items + [item(.tools, .small)])
        #expect(OverviewGrid.adding(items, widget: .media) == nil)
        let four = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .large)]
        #expect(OverviewGrid.adding(four, widget: .device) == nil)
    }

    @Test func removingTakesTheTileOut() {
        #expect(OverviewGrid.removing([item(.media, .wide), item(.timer, .small)], widget: .media) == [item(.timer, .small)])
    }

    @Test func aCellIsFoundByTheTileOnIt() {
        let items = [item(.media, .large), item(.calendar, .wide)]
        #expect(OverviewGrid.index(atColumn: 1, row: 1, in: items) == 0)
        #expect(OverviewGrid.index(atColumn: 3, row: 0, in: items) == 1)
        #expect(OverviewGrid.index(atColumn: 3, row: 1, in: items) == nil)
    }

    @Test func eachRowPastTwoMakesTheSheetTaller() {
        // At 100%: the tab row (32) and the page's margins (2 × 14) do not hold tiles.
        #expect(OverviewGrid.sheetHeight(rows: 2, chrome: 60) == nil)
        #expect(OverviewGrid.sheetHeight(rows: 3, chrome: 60) == 277)
        #expect(OverviewGrid.sheetHeight(rows: 4, chrome: 60) == 354)
    }

    @Test func anAddedRowIsAsTallAsTheFirstTwoAtEverySize() {
        // The tab row keeps the hardware notch's height while the page grows, so in sheet
        // points it is smaller on a larger notch: 32 at 100%, 25.6 at 125%, 21.3 at 150%.
        for header in [32.0, 25.6, 21.3] {
            let chrome = CGFloat(header) + 28
            let grid = { (sheet: CGFloat) in sheet - chrome + 2 * OverviewGrid.gridOutset }
            let usual = (grid(200) - OverviewGrid.gap) / 2
            for rows in 3...4 {
                let sheet = OverviewGrid.sheetHeight(rows: rows, chrome: chrome) ?? 0
                let row = (grid(sheet) - CGFloat(rows - 1) * OverviewGrid.gap) / CGFloat(rows)
                #expect(abs(row - usual) < 0.001)
            }
        }
    }

    @Test func theAddTileShowsWhileATileIsMissingAndThereIsRoom() {
        #expect(OverviewGrid.showsAddTile(OverviewGrid.defaultArrangement)) // tools is missing
        let full = [item(.media, .large), item(.calendar, .large), item(.timer, .large), item(.agents, .large)]
        #expect(!OverviewGrid.showsAddTile(full))
    }

    @Test func theAddTileCanTakeARowOfItsOwn() {
        // The default fills two rows; the add tile needs a third while editing.
        #expect(OverviewGrid.editingRows(OverviewGrid.defaultArrangement) == 3)
        #expect(OverviewGrid.editingRows([item(.media, .wide)]) == 2)
        // With no room for an add tile, the rows are the tiles' own.
        let full = [item(.media, .large), item(.calendar, .large), item(.timer, .large),
                    item(.agents, .wide), item(.device, .small), item(.tools, .small)]
        #expect(OverviewGrid.editingRows(full) == 4)
    }

    @Test func aDragLandsWhereTheTileUnderThePointerIs() {
        let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)]
        #expect(OverviewGrid.dropIndex(column: 3, row: 0, dragging: .timer, in: items) == 1)
        #expect(OverviewGrid.dropIndex(column: 0, row: 0, dragging: .agents, in: items) == 0)
        #expect(OverviewGrid.dropIndex(column: 3, row: 1, dragging: .media, in: items) == 3)
    }

    @Test func aDragShowsTheNewOrderAndIsSavedOnlyWhenDroppedOnTheGrid() {
        let items = [item(.media, .wide), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)]
        var drag = OverviewDrag(widget: .timer, from: items)
        drag.move(toColumn: 3, row: 0)
        drag.move(toColumn: 0, row: 0)
        #expect(drag.preview.map(\.widget) == [.timer, .media, .calendar, .agents])
        #expect(drag.drop(inside: true)?.map(\.widget) == [.timer, .media, .calendar, .agents])
        #expect(drag.drop(inside: false) == nil)
    }

    @Test func aDragBackToWhereItStartedSavesNothing() {
        let items = [item(.media, .wide), item(.timer, .small)]
        var drag = OverviewDrag(widget: .timer, from: items)
        drag.move(toColumn: 0, row: 0)
        drag.move(toColumn: 3, row: 1)
        #expect(drag.drop(inside: true) == nil)
    }

    @Test func aWideOrLargeTileLiftedAndPutBackSavesNothing() {
        // Picked up by any of its cells and barely moved: its top left stays where it was.
        var wide = OverviewDrag(widget: .calendar, from: OverviewGrid.defaultArrangement)
        wide.move(byColumns: 0, rows: 0)
        #expect(wide.preview == OverviewGrid.defaultArrangement)
        #expect(wide.drop(inside: true) == nil)
        let items = [item(.media, .large), item(.calendar, .wide), item(.timer, .small), item(.agents, .small)]
        var large = OverviewDrag(widget: .media, from: items)
        large.move(byColumns: 0, rows: 0)
        #expect(large.drop(inside: true) == nil)
    }

    @Test func aTileMovedByWholeCellsLandsWhereItsTopLeftGoes() {
        // The default: media and calendar wide on row 0, four small tiles on row 1.
        var drag = OverviewDrag(widget: .calendar, from: OverviewGrid.defaultArrangement)
        drag.move(byColumns: -2, rows: 0)
        #expect(drag.preview.map(\.widget) == [.calendar, .media, .timer, .agents, .clipboard, .device])
        // A wide tile cannot start in the last column: moving it right stays in the grid.
        var right = OverviewDrag(widget: .media, from: OverviewGrid.defaultArrangement)
        right.move(byColumns: 3, rows: 0)
        #expect(right.preview.map(\.widget) == [.calendar, .media, .timer, .agents, .clipboard, .device])
    }

    @Test func aTileCarriedOffTheGridShowsTheStartingOrder() {
        // Off the page the tile would go back, so the others go back to where they were.
        var drag = OverviewDrag(widget: .timer, from: OverviewGrid.defaultArrangement)
        drag.move(byColumns: 3, rows: 0)
        #expect(drag.preview != OverviewGrid.defaultArrangement)
        drag.moveOffGrid()
        #expect(drag.preview == OverviewGrid.defaultArrangement)
        #expect(drag.drop(inside: false) == nil)
    }

    @Test func sevenKindsEachInThreeSizes() {
        #expect(OverviewWidget.allCases.map(\.rawValue) == ["media", "calendar", "timer", "clipboard", "tools", "agents", "device"])
        #expect(OverviewWidget.allCases.allSatisfy { $0.sizes == [.small, .wide, .large] })
    }

    @Test func oldKindsBecomeTheirFeaturesWidgetAndKeepTheirSize() {
        #expect(OverviewGrid.arrangement(from: [
            "albumArt:large", "dayClock:small", "timerDisc:large", "colorPalette:wide",
            "usageRings:small", "deviceRings:wide", "tool.translate:small",
        ]) == [item(.media, .large), item(.calendar, .small), item(.timer, .large), item(.clipboard, .wide),
               item(.agents, .small), item(.device, .wide), item(.tools, .small)])
        #expect(OverviewGrid.arrangement(from: ["clipStack:large"]) == [item(.clipboard, .large)])
    }

    @Test func aSecondTileOfTheSameFeatureIsDropped() {
        #expect(OverviewGrid.arrangement(from: ["media:wide", "albumArt:large", "tool.capture:small", "tool.note:small", "tools:wide"])
                == [item(.media, .wide), item(.tools, .small)])
    }

    @Test func unknownEntriesAreStillDropped() {
        #expect(OverviewGrid.arrangement(from: ["tool:small", "weather:wide", "media:huge", "calendar:wide"]) == [item(.calendar, .wide)])
    }

    @Test func anArrangementIsRemembered() {
        let defaults = InMemoryDefaults()
        let store = OverviewSettingsStore(defaults: defaults)
        store.arrangement = [item(.timer, .large), item(.media, .small)]
        #expect(defaults.object(forKey: "shell.overviewArrangement") as? [String] == ["timer:large", "media:small"])
        #expect(OverviewSettingsStore(defaults: defaults).arrangement == [item(.timer, .large), item(.media, .small)])
    }

    @Test func withNothingSavedTheDefaultIsUsed() {
        #expect(OverviewSettingsStore(defaults: InMemoryDefaults()).arrangement == OverviewGrid.defaultArrangement)
        #expect(OverviewGrid.defaultArrangement.map(\.widget) == [.media, .calendar, .timer, .agents, .clipboard, .device])
        #expect(OverviewGrid.place(OverviewGrid.defaultArrangement).rows == 2)
    }

    @Test func tilesHiddenBeforeStayHidden() {
        let defaults = InMemoryDefaults()
        defaults.set(["timer", "media"], forKey: "shell.hiddenOverviewWidgets")
        #expect(OverviewSettingsStore(defaults: defaults).arrangement.map(\.widget) == [.calendar, .agents, .clipboard, .device])
    }

    @Test func damagedEntriesAreDropped() {
        let defaults = InMemoryDefaults()
        defaults.set(
            ["media:wide", "weather:small", "timer:huge", "media:small", "nonsense", "agents:large"],
            forKey: "shell.overviewArrangement")
        #expect(OverviewSettingsStore(defaults: defaults).arrangement == [item(.media, .wide), item(.agents, .large)])
    }

    @Test func anArrangementTooTallLosesItsLastTiles() {
        let defaults = InMemoryDefaults()
        defaults.set(
            ["media:large", "calendar:large", "timer:large", "agents:large", "device:small"],
            forKey: "shell.overviewArrangement")
        #expect(OverviewSettingsStore(defaults: defaults).arrangement.map(\.widget) == [.media, .calendar, .timer, .agents])
    }

    @Test func anEmptyArrangementStaysEmpty() {
        let defaults = InMemoryDefaults()
        defaults.set([String](), forKey: "shell.overviewArrangement")
        #expect(OverviewSettingsStore(defaults: defaults).arrangement.isEmpty)
    }
}

private func item(_ widget: OverviewWidget, _ size: WidgetSize) -> OverviewItem {
    OverviewItem(widget: widget, size: size)
}
