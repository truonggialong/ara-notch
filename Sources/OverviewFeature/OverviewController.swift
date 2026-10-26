import NotchShell
import OverviewCore
import SwiftUI

/// The overview page: the features' widgets on a grid the user arranges on the notch. The
/// app hands over each feature's widget once everything they show has been made.
@MainActor
public final class OverviewController {
    public let settings: OverviewSettings
    private let editor: OverviewEditor
    private let tiles = OverviewTiles()

    /// A trial run given an arrangement of its own shows it and keeps its changes in memory.
    public init(settings: OverviewSettings, trialArrangement: [OverviewItem]? = nil) {
        self.settings = settings
        editor = OverviewEditor(settings: settings, trialArrangement: trialArrangement)
    }

    /// The page, tied to the notch: it asks for a taller sheet when its tiles take more than
    /// two rows, and its edit mode ends when the notch closes or another page shows.
    public func makePage(notch: NotchController) -> NotchPage {
        editor.connect(to: notch)
        let editor = editor, tiles = tiles
        var page = NotchPage(
            id: OverviewLayout.pageID, titleKey: "page.overview.title", symbolName: "square.grid.2x2"
        ) { [weak notch] in
            OverviewPage(editor: editor, tiles: tiles.tiles) { rows in
                guard let notch else { return }
                notch.setSheetHeight(
                    OverviewGrid.sheetHeight(rows: rows, chrome: notch.pageChrome), forPage: OverviewLayout.pageID)
            }
        }
        page.headerAccessory = { AnyView(OverviewEditButton(editor: editor)) }
        return page
    }

    /// Each feature's widget, by the tile it fills.
    public func setTiles(_ tiles: [OverviewWidget: AnyView]) {
        self.tiles.tiles = tiles
    }

    /// The overview's line in Settings › Notch pages.
    public func makeSettingsRow() -> AnyView {
        AnyView(OverviewSettingsRow(settings: settings))
    }

    /// Starts arranging the tiles, as the page's edit button does; with no tile the choice of
    /// tiles opens at once, as the empty page's own button does.
    public func beginEditing() {
        editor.begin()
        editor.isChoosingTile = editor.arrangement.isEmpty
    }
}

/// The overview's tiles, made by their features after the page itself was registered.
@MainActor
final class OverviewTiles {
    var tiles: [OverviewWidget: AnyView] = [:]
}
