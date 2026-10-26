import ClipboardCore
import Foundation
import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct QuickDeleteTests {
    private func clip(_ id: Int64) -> ClipItem {
        ClipItem(
            id: id, kind: .text, text: "mục \(id)", blobName: nil, source: ClipSource(bundleID: nil, appName: nil),
            createdAt: Date(), lastUsedAt: Date(), byteSize: 5)
    }

    @Test func aSecondClickRightAfterADeleteDoesNotDeleteTheCardThatSlidIn() {
        let model = ClipboardViewModel()
        var deleted: [Int64] = []
        model.onDelete = { deleted.append($0.id) }
        let start = Date()
        model.quickDelete(clip(1), at: start)
        model.quickDelete(clip(2), at: start.addingTimeInterval(0.2))
        #expect(deleted == [1])
    }

    @Test func deletingAgainAfterAMomentWorks() {
        let model = ClipboardViewModel()
        var deleted: [Int64] = []
        model.onDelete = { deleted.append($0.id) }
        let start = Date()
        model.quickDelete(clip(1), at: start)
        model.quickDelete(clip(2), at: start.addingTimeInterval(1))
        #expect(deleted == [1, 2])
    }
}
