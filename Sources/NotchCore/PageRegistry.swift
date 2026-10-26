/// Identity and tab appearance of one notch page.
public struct PageDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    /// Localization key of the page title.
    public let titleKey: String
    /// SF Symbol shown on the page's tab.
    public let symbolName: String

    public init(id: String, titleKey: String, symbolName: String) {
        self.id = id
        self.titleKey = titleKey
        self.symbolName = symbolName
    }
}

/// The notch's pages: which exist, in what order, which are hidden, and which is selected.
public struct PageRegistry: Equatable, Sendable {
    /// Pages in registration order.
    private var registered: [PageDescriptor] = []
    /// The order asked for; may name pages that are not registered (yet).
    private var requestedOrder: [String] = []
    private var requestedHidden: Set<String> = []
    /// False until a page was chosen; until then the first visible page is selected.
    private var hasChosenPage = false

    public private(set) var selectedID: String?

    public init() {}

    /// Every registered page, hidden ones included: pages of the requested order first, the
    /// rest in registration order.
    public var allPages: [PageDescriptor] {
        let ordered = requestedOrder.compactMap { id in registered.first { $0.id == id } }
        return ordered + registered.filter { !requestedOrder.contains($0.id) }
    }

    /// Ids of `allPages`, in order.
    public var order: [String] {
        allPages.map(\.id)
    }

    /// The pages that are hidden. Never all of them: the first page shows if every page is asked hidden.
    public var hiddenIDs: Set<String> {
        let all = allPages
        var hidden = requestedHidden.intersection(all.map(\.id))
        if hidden.count == all.count, let first = all.first {
            hidden.remove(first.id)
        }
        return hidden
    }

    /// The pages shown as tabs, in order.
    public var pages: [PageDescriptor] {
        let hidden = hiddenIDs
        return allPages.filter { !hidden.contains($0.id) }
    }

    /// Appends the page; a page whose id is already registered is ignored.
    public mutating func register(_ page: PageDescriptor) {
        guard !registered.contains(where: { $0.id == page.id }) else { return }
        registered.append(page)
        repairSelection()
    }

    /// A saved page order with `pageID` put in front when it is missing: a page added later
    /// that should lead, for orders kept from before it existed. An empty order means none
    /// was ever chosen and is left alone.
    public static func order(_ order: [String], leading pageID: String?) -> [String] {
        guard let pageID, !order.isEmpty, !order.contains(pageID) else { return order }
        return [pageID] + order
    }

    /// Sets the order and the hidden pages at once, as read from the settings.
    public mutating func applyLayout(order: [String], hidden: [String]) {
        requestedOrder = order
        requestedHidden = Set(hidden)
        repairSelection()
    }

    /// Hides or shows a page. Hiding the last visible page is refused.
    public mutating func setHidden(_ isHidden: Bool, id: String) {
        if isHidden {
            guard pages.contains(where: { $0.id == id }), pages.count > 1 else { return }
            requestedHidden.insert(id)
        } else {
            requestedHidden.remove(id)
        }
        repairSelection()
    }

    /// Moves a page up (negative) or down in the full list; a move past either end is ignored.
    public mutating func move(id: String, by offset: Int) {
        var ids = order
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        requestedOrder = ids
        repairSelection()
    }

    /// Selects a visible page; anything else is ignored.
    public mutating func select(_ id: String) {
        guard pages.contains(where: { $0.id == id }) else { return }
        selectedID = id
        hasChosenPage = true
    }

    public mutating func selectNext() {
        step(by: 1)
    }

    public mutating func selectPrevious() {
        step(by: -1)
    }

    private mutating func step(by offset: Int) {
        let pages = pages
        guard pages.count > 1, let index = pages.firstIndex(where: { $0.id == selectedID }) else { return }
        selectedID = pages[(index + offset + pages.count) % pages.count].id
        hasChosenPage = true
    }

    /// Keeps the selection on a visible page.
    private mutating func repairSelection() {
        let pages = pages
        if !hasChosenPage || !pages.contains(where: { $0.id == selectedID }) {
            selectedID = pages.first?.id
        }
    }
}

/// Where the tabs of the open notch go. The hardware notch sits in the middle of the row and
/// hides whatever is drawn behind it, so tabs fill the room on its left and carry on to its right.
public enum TabRowLayout {
    /// The room for tabs on one side of the notch.
    public static func sideWidth(rowWidth: Double, notchWidth: Double, edgePadding: Double, notchGap: Double) -> Double {
        max((rowWidth - notchWidth) / 2 - edgePadding - notchGap, 0)
    }

    /// How many of `count` tabs sit left of the notch; the rest go to its right. One always
    /// stays on the left, however little room there is.
    public static func leftCount(count: Int, sideWidth: Double, tabWidth: Double, spacing: Double) -> Int {
        guard count > 0 else { return 0 }
        let fitting = Int(((sideWidth + spacing) / (tabWidth + spacing)).rounded(.down))
        return min(count, max(fitting, 1))
    }
}
