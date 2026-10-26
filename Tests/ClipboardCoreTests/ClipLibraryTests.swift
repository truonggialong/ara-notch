import Foundation
import Testing
@testable import ClipboardCore

private func item(_ id: Int64, _ kind: ClipKind, _ text: String = "", app: String? = nil) -> ClipItem {
    makeItem(id: id, kind: kind, text: text, appName: app)
}

private let items = [
    item(1, .text, "ghi chú họp", app: "Notes"),
    item(2, .link, "https://example.com", app: "Safari"),
    item(3, .text, "let x = 1", app: "Code"),
    item(4, .image, app: "Safari"),
    item(5, .color, "#4A90D9", app: "Code"),
    item(6, .text, "không rõ nguồn"),
    item(7, .link, "https://apple.com", app: "Safari"),
]
private let boards = [
    ClipBoard(id: 10, name: "Công việc", symbolName: "briefcase", itemCount: 2),
    ClipBoard(id: 11, name: "Két", symbolName: "lock", itemCount: 3, isLocked: true),
    ClipBoard(id: 12, name: "Trống", symbolName: "tray", itemCount: 0),
]
private let membership: [Int64: Set<Int64>] = [1: [10], 5: [10, 12], 99: [10]]

@Suite struct LibrarySidebarTests {
    private let sidebar = LibrarySidebar(items: items, boards: boards, membership: membership)

    @Test func countsEverything() {
        #expect(sidebar.total == 7)
    }

    @Test func listsKindsInFixedOrderWithoutEmptyOnes() {
        #expect(sidebar.kinds == [
            .init(filter: .kind(.text), title: "text", count: 3),
            .init(filter: .kind(.link), title: "link", count: 2),
            .init(filter: .kind(.color), title: "color", count: 1),
            .init(filter: .kind(.image), title: "image", count: 1),
        ])
    }

    @Test func listsSourceAppsMostUsedFirstThenByName() {
        #expect(sidebar.apps == [
            .init(filter: .app("Safari"), title: "Safari", count: 3),
            .init(filter: .app("Code"), title: "Code", count: 2),
            .init(filter: .app("Notes"), title: "Notes", count: 1),
        ])
    }

    @Test func listsBoardsWithTheClipsActuallyInTheHistory() {
        // Clip 99 is pinned but not in the list. The locked board's clips are not in the plain
        // history; it is listed with its lock and the count the store keeps.
        #expect(sidebar.boards == [
            .init(filter: .board(10), title: "Công việc", symbolName: "briefcase", count: 2),
            .init(filter: .board(11), title: "Két", symbolName: "lock", count: 3, isLocked: true),
            .init(filter: .board(12), title: "Trống", symbolName: "tray", count: 1),
        ])
    }

    @Test func knowsWhichFiltersStillExist() {
        #expect(sidebar.contains(.all))
        #expect(sidebar.contains(.kind(.image)))
        #expect(sidebar.contains(.app("Code")))
        #expect(sidebar.contains(.board(12)))
        #expect(!sidebar.contains(.kind(.file)))
        #expect(!sidebar.contains(.app("Mail")))
        #expect(sidebar.contains(.board(11)))
        #expect(!sidebar.contains(.board(13)))
    }
}

@Suite struct LibraryFilterTests {
    private func ids(_ filter: LibraryFilter, search: String = "") -> [Int64] {
        filter.items(from: items, membership: membership, search: search).map(\.id)
    }

    @Test func allKeepsTheOrder() {
        #expect(ids(.all) == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test func filtersByKindAppAndBoard() {
        #expect(ids(.kind(.link)) == [2, 7])
        #expect(ids(.app("Safari")) == [2, 4, 7])
        #expect(ids(.board(10)) == [1, 5])
        #expect(ids(.board(11)).isEmpty)
    }

    @Test func searchNarrowsTheFilteredClips() {
        #expect(ids(.app("Safari"), search: "apple") == [7])
        #expect(ids(.all, search: "@text hop") == [1])
        #expect(ids(.kind(.image), search: "apple").isEmpty)
    }
}
