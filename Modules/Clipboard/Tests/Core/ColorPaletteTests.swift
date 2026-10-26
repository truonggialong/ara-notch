import Foundation
import Testing
@testable import ClipboardCore

@Suite struct ColorPaletteTests {
    @Test func newestColorsOnceEachWithoutLockedOnes() {
        let plain = makeItem(id: 9, kind: .color, text: "#00FF00")
        let locked = ClipItem(
            id: 9, kind: .color, text: "#00FF00", blobName: nil, isEncrypted: true,
            source: plain.source, createdAt: plain.createdAt, lastUsedAt: plain.lastUsedAt, byteSize: 7)
        let items = [
            makeItem(id: 1, kind: .color, text: "#4A90D9"), makeItem(id: 2, kind: .text, text: "hello"),
            locked, makeItem(id: 3, kind: .color, text: "#4a90d9"), makeItem(id: 4, kind: .color, text: "rgb(255, 0, 0)"),
            makeItem(id: 5, kind: .color, text: "#123456"),
        ]
        #expect(ColorPalette.recent(items, limit: 5).map(\.id) == [1, 4, 5])
        #expect(ColorPalette.recent(items, limit: 2).map(\.id) == [1, 4])
    }
}

@Suite struct ClipTodayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func clip(_ id: Int64, usedHoursAgo hours: Double, now: Date, locked: Bool = false) -> ClipItem {
        let used = now.addingTimeInterval(-hours * 3600)
        return ClipItem(
            id: id, kind: .text, text: "t\(id)", blobName: nil, isEncrypted: locked,
            source: ClipSource(bundleID: nil, appName: nil), createdAt: used, lastUsedAt: used, byteSize: 2)
    }

    @Test func countsTheClipsUsedTodayWithoutLockedOnes() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15))!
        let items = [clip(1, usedHoursAgo: 0.1, now: now), clip(2, usedHoursAgo: 2, now: now, locked: true),
                     clip(3, usedHoursAgo: 14, now: now), clip(4, usedHoursAgo: 16, now: now)]
        #expect(ClipToday.count(items, now: now, calendar: calendar) == 2)
    }

    @Test func stopsAtTheFirstClipFromAnEarlierDay() {
        // The history is kept last used first: past the first older clip there is no clip of today.
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 15))!
        let items = [clip(1, usedHoursAgo: 1, now: now), clip(2, usedHoursAgo: 30, now: now), clip(3, usedHoursAgo: 0.5, now: now)]
        #expect(ClipToday.count(items, now: now, calendar: calendar) == 1)
    }
}
