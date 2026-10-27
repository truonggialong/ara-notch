import Foundation
import Testing
@testable import NotesFeature

/// Groups of the Notes window's list, on a fixed day in a fixed time zone.
@Suite struct NoteListGroupingTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func note(_ id: String, _ modified: Date) -> NoteSummary {
        NoteSummary(id: id, name: id, folderID: "f", modified: modified, snippet: "", hasImages: false, isLocked: false)
    }

    private static let now = date(2026, 10, 27, 15)

    @Test func groupsByDay() {
        let notes = [
            Self.note("monthsAgo", Self.date(2026, 8, 27)),
            Self.note("today", Self.date(2026, 10, 27)),
            Self.note("threeDays", Self.date(2026, 10, 24)),
            Self.note("yesterday", Self.date(2026, 10, 26)),
        ]
        let groups = NoteListGrouping.groups(notes, now: Self.now, calendar: Self.calendar)
        #expect(groups.map(\.titleKey) == ["notes.group.today", "notes.group.yesterday", "notes.group.previous7",
                                          "notes.group.month"])
        #expect(groups.map { $0.notes.map(\.id) } == [["today"], ["yesterday"], ["threeDays"], ["monthsAgo"]])
    }

    @Test func olderNotesGoByMonthNewestFirst() {
        let notes = [
            Self.note("july", Self.date(2026, 7, 2)),
            Self.note("twentyDays", Self.date(2026, 10, 7)),
            Self.note("augustLate", Self.date(2026, 8, 30)),
            Self.note("augustEarly", Self.date(2026, 8, 1)),
            Self.note("lastYear", Self.date(2025, 8, 15)),
        ]
        let groups = NoteListGrouping.groups(notes, now: Self.now, calendar: Self.calendar)
        #expect(groups.map(\.titleKey) == ["notes.group.previous30", "notes.group.month", "notes.group.month",
                                          "notes.group.month"])
        #expect(groups.map { $0.notes.map(\.id) } == [["twentyDays"], ["augustLate", "augustEarly"], ["july"], ["lastYear"]])
        let english = Locale(identifier: "en_US")
        #expect(NoteListGrouping.monthTitle(of: Self.date(2026, 8, 1), now: Self.now, calendar: Self.calendar,
                                            locale: english) == "August")
        #expect(NoteListGrouping.monthTitle(of: Self.date(2025, 8, 15), now: Self.now, calendar: Self.calendar,
                                            locale: english) == "August 2025")
    }

    @Test func aDayStartsAtMidnightInTheCalendarsTimeZone() {
        let notes = [Self.note("lateYesterday", Self.date(2026, 10, 26, 23)), Self.note("early", Self.date(2026, 10, 27, 0))]
        let groups = NoteListGrouping.groups(notes, now: Self.now, calendar: Self.calendar)
        #expect(groups.map(\.titleKey) == ["notes.group.today", "notes.group.yesterday"])
    }
}
