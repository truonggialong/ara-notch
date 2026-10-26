import Combine
import Foundation
import NotchCore
import NotchShell
import OverviewCore

/// The overview's arrangement as the page shows it, and the edit mode that changes it on the
/// notch. Saved in the settings, except on a trial run given an arrangement of its own, whose
/// changes stay in memory.
@MainActor
final class OverviewEditor: ObservableObject {
    @Published private(set) var arrangement: [OverviewItem]
    @Published private(set) var isEditing = false
    /// The features not on the page, offered as chips by the "Add tile" tile.
    @Published var isChoosingTile = false
    /// The tile whose size button just found no other size that fits; it says "No room".
    @Published private(set) var refusedWidget: OverviewWidget?
    /// How often each tile has been refused a size: its shake follows this count, which only
    /// goes up, so the shake plays when the "No room" label comes and not again when it goes.
    @Published private(set) var refusals: [OverviewWidget: Int] = [:]
    /// A tile being dragged to a new place: the page shows its preview meanwhile.
    @Published private(set) var drag: OverviewDrag?
    /// How far the dragged tile has moved from where it was picked up.
    @Published private(set) var dragTranslation = CGSize.zero

    /// The arrangement the page shows: the drag's preview while a tile is dragged.
    var shown: [OverviewItem] {
        drag?.preview ?? arrangement
    }

    private let settings: OverviewSettings
    private let saves: Bool
    private var cancellables = Set<AnyCancellable>()
    private var refusal: DispatchWorkItem?
    /// Tells the notch the page is being edited: it then stays while the pointer is away.
    private var setEditing: (Bool) -> Void = { _ in }

    init(settings: OverviewSettings, trialArrangement: [OverviewItem]? = nil) {
        self.settings = settings
        saves = trialArrangement == nil
        arrangement = trialArrangement ?? settings.arrangement
        if saves {
            // Settings can change it too (Reset layout).
            settings.$arrangement
                .removeDuplicates()
                .sink { [weak self] in self?.arrangement = $0 }
                .store(in: &cancellables)
        }
    }

    /// Ties the edit mode to the notch: it ends when the notch closes or another page shows.
    func connect(to notch: NotchController) {
        setEditing = { [weak notch] in notch?.setBeingEdited($0, forPage: OverviewLayout.pageID) }
        notch.isOpenPublisher
            .filter { !$0 }
            .sink { [weak self] _ in self?.end() }
            .store(in: &cancellables)
        notch.selectedPagePublisher
            .filter { $0 != OverviewLayout.pageID }
            .sink { [weak self] _ in self?.end() }
            .store(in: &cancellables)
    }

    /// Shows the arrangement and keeps it.
    func save(_ items: [OverviewItem]) {
        arrangement = items
        if saves {
            settings.arrangement = items
        }
    }

    func begin() {
        guard !isEditing else { return }
        isEditing = true
        setEditing(true)
    }

    func end() {
        guard isEditing else { return }
        isEditing = false
        isChoosingTile = false
        refusedWidget = nil
        cancelDrag()
        setEditing(false)
    }

    func remove(_ widget: OverviewWidget) {
        save(OverviewGrid.removing(arrangement, widget: widget))
    }

    func resize(_ widget: OverviewWidget) {
        if let resized = OverviewGrid.resized(arrangement, widget: widget) {
            save(resized)
        } else {
            refuse(widget)
        }
    }

    func add(_ widget: OverviewWidget) {
        guard let added = OverviewGrid.adding(arrangement, widget: widget) else { return }
        save(added)
        if !OverviewGrid.showsAddTile(added) {
            isChoosingTile = false
        }
    }

    /// The pointer moved, holding a tile, this far from where it picked the tile up; the
    /// tile would land that many whole cells away, or go back when the pointer is off the grid.
    func dragTile(_ widget: OverviewWidget, byColumns columns: Int, rows: Int, translation: CGSize, isOnGrid: Bool) {
        guard isEditing else { return }
        if drag?.widget != widget {
            drag = OverviewDrag(widget: widget, from: arrangement)
        }
        dragTranslation = translation
        if isOnGrid {
            drag?.move(byColumns: columns, rows: rows)
        } else {
            drag?.moveOffGrid()
        }
    }

    /// The tile was let go: on the grid its new place is kept, elsewhere nothing changes.
    func dropTile(inside: Bool) {
        if let kept = drag?.drop(inside: inside) {
            save(kept)
        }
        cancelDrag()
    }

    func cancelDrag() {
        drag = nil
        dragTranslation = .zero
    }

    /// The features that are not on the page and still fit, in the order of `OverviewTileGroup`.
    var addableWidgets: [OverviewWidget] {
        OverviewTileGroup.allCases
            .compactMap { feature in OverviewWidget.allCases.first { $0.feature == feature } }
            .filter { OverviewGrid.adding(arrangement, widget: $0) != nil }
    }

    private func refuse(_ widget: OverviewWidget) {
        refusal?.cancel()
        refusedWidget = widget
        refusals[widget, default: 0] += 1
        let clear = DispatchWorkItem { [weak self] in self?.refusedWidget = nil }
        refusal = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: clear)
    }
}
