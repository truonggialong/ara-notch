import Foundation
import Testing
@testable import ClipboardCore

@Suite struct ClipKindTallyTests {
    @Test func countsEachKindThatIsPresentInAFixedOrder() {
        let items = [
            makeItem(id: 1, kind: .image), makeItem(id: 2, kind: .text), makeItem(id: 3, kind: .link),
            makeItem(id: 4, kind: .text), makeItem(id: 5, kind: .file),
        ]
        let tally = ClipKindTally(items)
        #expect(tally.total == 5)
        // Text, links, pictures, colours, files; a kind with nothing is left out.
        #expect(tally.kinds.map(\.kind) == [.text, .link, .image, .file])
        #expect(tally.kinds.map(\.count) == [2, 1, 1, 1])
    }

    @Test func anEmptyHistoryHasNoKinds() {
        let tally = ClipKindTally([])
        #expect(tally.total == 0)
        #expect(tally.kinds.isEmpty)
    }

    @Test func aKindsChipTypesItsFilterAndASecondClickClearsIt() {
        #expect(ClipKindTally.search(toggling: .link, in: "") == "@link")
        #expect(ClipKindTally.search(toggling: .link, in: "@link") == "")
        // Another kind replaces the one in the search; the words typed beside it stay.
        #expect(ClipKindTally.search(toggling: .image, in: "@link") == "@image")
        #expect(ClipKindTally.search(toggling: .image, in: "report @link") == "report @image")
        #expect(ClipKindTally.search(toggling: .link, in: "report @link") == "report")
        // A filter by app is not a kind and is kept.
        #expect(ClipKindTally.search(toggling: .text, in: "@safari") == "@safari @text")
    }

    @Test func tellsWhichKindASearchIsNarrowedTo() {
        #expect(ClipKindTally.kind(in: "@link") == .link)
        #expect(ClipKindTally.kind(in: "hello") == nil)
        #expect(ClipKindTally.kind(in: "@safari") == nil)
    }

    @Test func aChipReplacesAKindTypedInVietnamese() {
        #expect(ClipKindTally.search(toggling: .color, in: "@ảnh báo cáo") == "báo cáo @color")
    }
}
