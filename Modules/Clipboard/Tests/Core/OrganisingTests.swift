import Foundation
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

@Suite struct ClipReminderPresetTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func theShortPresetsCountFromNow() {
        #expect(ClipReminderPreset.inThirtyMinutes.due(from: at(12, 10), calendar: calendar) == at(12, 10, 30))
        #expect(ClipReminderPreset.inOneHour.due(from: at(12, 10), calendar: calendar) == at(12, 11))
        #expect(ClipReminderPreset.inThreeHours.due(from: at(12, 23), calendar: calendar) == at(13, 2))
    }

    @Test func thisEveningIsEightOClockOrTomorrowWhenThatHasPassed() {
        #expect(ClipReminderPreset.thisEvening.due(from: at(12, 10), calendar: calendar) == at(12, 20))
        #expect(ClipReminderPreset.thisEvening.due(from: at(12, 21), calendar: calendar) == at(13, 20))
    }

    @Test func tomorrowMorningIsNineOClockTheNextDay() {
        #expect(ClipReminderPreset.tomorrowMorning.due(from: at(12, 10), calendar: calendar) == at(13, 9))
        #expect(ClipReminderPreset.tomorrowMorning.due(from: at(12, 23, 59), calendar: calendar) == at(13, 9))
    }

    @Test func aReminderTakesItsWordsFromTheClip() {
        var item = makeItem(text: "Gửi báo giá cho anh Minh\nKèm bảng tính quý 3")
        #expect(ClipReminderText.title(for: item, fallback: "Clip") == "Gửi báo giá cho anh Minh")
        #expect(ClipReminderText.notes(for: item) == "Gửi báo giá cho anh Minh\nKèm bảng tính quý 3")
        item.title = "Báo giá"
        #expect(ClipReminderText.title(for: item, fallback: "Clip") == "Báo giá")
    }

    @Test func aLongFirstLineIsCutForTheTitle() {
        let item = makeItem(text: String(repeating: "dài ", count: 60))
        #expect(ClipReminderText.title(for: item, fallback: "Clip").count <= 81)
    }

    @Test func aPictureGetsTheFallbackTitleAndNoNotes() {
        let item = makeItem(kind: .image, text: "")
        #expect(ClipReminderText.title(for: item, fallback: "Ảnh") == "Ảnh")
        #expect(ClipReminderText.notes(for: item) == nil)
    }
}

@Suite struct SavedFilterTests {
    @Test func aSearchCanBeSavedAndComesBack() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.savedFilters.isEmpty)
        store.savedFilters = SavedFilter.adding("@link apple", to: store.savedFilters)
        #expect(ClipboardSettingsStore(defaults: defaults).savedFilters == [SavedFilter(query: "@link apple")])
    }

    @Test func theSameSearchIsNotSavedTwice() {
        var filters = SavedFilter.adding("@image hoá đơn", to: [])
        filters = SavedFilter.adding("  @image hoá đơn ", to: filters)
        #expect(filters.count == 1)
    }

    @Test func anEmptySearchIsNotSaved() {
        #expect(SavedFilter.adding("   ", to: []).isEmpty)
    }

    @Test func onlySoManyAreKept() {
        var filters: [SavedFilter] = []
        for index in 0..<20 {
            filters = SavedFilter.adding("tìm \(index)", to: filters)
        }
        #expect(filters.count == SavedFilter.limit)
        // The oldest give way to the newest.
        #expect(filters.last?.query == "tìm 19")
    }

    @Test func aFilterCanBeRemoved() {
        let filters = SavedFilter.adding("b", to: SavedFilter.adding("a", to: []))
        #expect(SavedFilter.removing("a", from: filters) == [SavedFilter(query: "b")])
    }
}

@Suite struct ClipSortOrderTests {
    private func item(_ id: Int64, _ text: String, created: TimeInterval, used: TimeInterval, title: String? = nil) -> ClipItem {
        ClipItem(
            id: id, kind: .text, text: text, blobName: nil, source: ClipSource(bundleID: nil, appName: nil),
            createdAt: date(created), lastUsedAt: date(used), byteSize: text.utf8.count, title: title)
    }

    private var items: [ClipItem] {
        [
            item(1, "chuối", created: 10, used: 90),
            item(2, "Ánh", created: 30, used: 40),
            item(3, "bưởi", created: 20, used: 50, title: "Zebra"),
        ]
    }

    @Test func recentlyUsedIsTheOrderTheHistoryComesIn() {
        #expect(ClipSortOrder.recentlyUsed.sorted(items).map(\.id) == [1, 2, 3])
    }

    @Test func newestAndOldestGoByWhenAClipWasFirstCopied() {
        #expect(ClipSortOrder.newest.sorted(items).map(\.id) == [2, 3, 1])
        #expect(ClipSortOrder.oldest.sorted(items).map(\.id) == [1, 3, 2])
    }

    @Test func byNameUsesTheTitleThenTheTextAndIgnoresAccents() {
        // "Ánh" sorts with A, the clip named "Zebra" goes last although its text starts with b.
        #expect(ClipSortOrder.name.sorted(items).map(\.id) == [2, 1, 3])
    }

    @Test func theOrderIsRemembered() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.sortOrder == .recentlyUsed)
        store.sortOrder = .name
        #expect(ClipboardSettingsStore(defaults: defaults).sortOrder == .name)
    }
}
