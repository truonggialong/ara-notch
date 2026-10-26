import ClipboardCore
import Foundation
import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct LibrarySortTests {
    private func clip(_ id: Int64, _ text: String, minutesAgo: Double) -> ClipItem {
        let date = Date().addingTimeInterval(-minutesAgo * 60)
        return ClipItem(
            id: id, kind: .text, text: text, blobName: nil, source: ClipSource(bundleID: nil, appName: nil),
            createdAt: date, lastUsedAt: date, byteSize: text.utf8.count)
    }

    @Test func theLibraryListsClipsInTheChosenOrder() {
        let model = ClipboardViewModel()
        model.items = [clip(1, "chuối", minutesAgo: 1), clip(2, "anh đào", minutesAgo: 2), clip(3, "bưởi", minutesAgo: 3)]
        model.sortOrder = .name
        let library = LibraryModel()
        #expect(library.visibleItems(of: model).map(\.text) == ["anh đào", "bưởi", "chuối"])
    }
}
