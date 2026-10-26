import Foundation
import Testing
@testable import CalendarCore

@Suite struct DayAgendaTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, calendarName: "", location: nil)
    }

    @Test func aDaysEventsAreThoseThatTouchItAllDayOnesFirstThenByStart() {
        let events = [
            event("late", at(14, 15), at(14, 16)),
            event("early", at(14, 9), at(14, 10)),
            event("birthday", at(14, 0), at(15, 0), allDay: true),
            event("yesterday", at(13, 9), at(13, 10)),
            event("overnight", at(13, 23), at(14, 1)),
            event("tomorrow", at(15, 9), at(15, 10)),
        ]
        let day = DayAgenda.events(on: at(14, 12), from: events, calendar: calendar)
        #expect(day.map(\.id) == ["birthday", "overnight", "early", "late"])
    }

    @Test func anEventEndingAtMidnightBelongsToTheDayBeforeOnly() {
        let events = [event("allDay13", at(13, 0), at(14, 0), allDay: true)]
        #expect(DayAgenda.events(on: at(14, 8), from: events, calendar: calendar).isEmpty)
        #expect(DayAgenda.events(on: at(13, 8), from: events, calendar: calendar).count == 1)
    }

    @Test func movingByWeeksKeepsTheWeekday() {
        let wednesday = at(14, 12)
        let next = WeekStrip.shifting(wednesday, weeks: 1, calendar: calendar)
        #expect(calendar.component(.day, from: next) == 21)
        #expect(calendar.component(.weekday, from: next) == calendar.component(.weekday, from: wednesday))
        let previous = WeekStrip.shifting(wednesday, weeks: -2, calendar: calendar)
        #expect(calendar.component(.day, from: previous) == 30)
        #expect(calendar.component(.month, from: previous) == 9)
        // The result is the start of that day, whatever the time given.
        #expect(next == calendar.startOfDay(for: next))
    }
}

@Suite struct EventDraftTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func aNewEventTodayStartsAtTheNextHalfHour() {
        #expect(EventDraft.defaultStartMinutes(on: at(12, 0), now: at(12, 15, 10), calendar: calendar) == 15 * 60 + 30)
        #expect(EventDraft.defaultStartMinutes(on: at(12, 0), now: at(12, 15, 30), calendar: calendar) == 16 * 60)
        #expect(EventDraft.defaultStartMinutes(on: at(12, 0), now: at(12, 15, 31), calendar: calendar) == 16 * 60)
        // Too late in the day for another half hour: the last one offered.
        #expect(EventDraft.defaultStartMinutes(on: at(12, 0), now: at(12, 23, 50), calendar: calendar) == 23 * 60 + 30)
    }

    @Test func aNewEventOnAnotherDayStartsAtNine() {
        #expect(EventDraft.defaultStartMinutes(on: at(15, 0), now: at(12, 15, 10), calendar: calendar) == 9 * 60)
    }

    @Test func aTimedEventLastsAnHourFromItsStart() throws {
        let draft = EventDraft(title: "  Call  ", day: at(15, 13), startMinutes: 9 * 60 + 30)
        let interval = try #require(draft.interval(calendar: calendar))
        #expect(interval.start == at(15, 9, 30))
        #expect(interval.end == at(15, 10, 30))
        #expect(draft.trimmedTitle == "Call")
        #expect(!draft.isAllDay)
    }

    @Test func anAllDayEventCoversTheWholeDay() throws {
        let draft = EventDraft(title: "Trip", day: at(15, 13), startMinutes: nil)
        let interval = try #require(draft.interval(calendar: calendar))
        #expect(draft.isAllDay)
        #expect(interval.start == at(15, 0))
        #expect(interval.end == at(16, 0))
    }

    @Test func anEventWithNoTitleIsNotMade() {
        #expect(EventDraft(title: "   ", day: at(15, 0), startMinutes: 540).interval(calendar: calendar) == nil)
    }

    @Test func timesAreOfferedEveryHalfHour() {
        #expect(EventDraft.timeChoices.count == 48)
        #expect(EventDraft.timeChoices.first == 0)
        #expect(EventDraft.timeChoices.last == 23 * 60 + 30)
    }
}

@Suite struct CalendarLinkTests {
    @Test func anEventOpensInTheCalendarAppByItsIdentifier() {
        let start = Date(timeIntervalSince1970: 1_792_047_600)
        let url = CalendarLinks.event(itemID: "ABC-123", start: start, isRepeating: false)
        #expect(url?.absoluteString == "ical://ekevent/ABC-123?method=show&options=more")
        #expect(CalendarLinks.event(itemID: "", start: start, isRepeating: false) == nil)
    }

    @Test func oneOccurrenceOfARepeatingEventIsNamedByItsStart() {
        // 15 October 2026, 07:00 in Greenwich; the calendar app reads the time that way.
        let start = Date(timeIntervalSince1970: 1_792_047_600)
        let url = CalendarLinks.event(itemID: "ABC-123", start: start, isRepeating: true)
        #expect(url?.absoluteString == "ical://ekevent/20261015T070000Z/ABC-123?method=show&options=more")
    }

    @Test func aReminderOpensInTheRemindersAppByItsIdentifier() {
        #expect(CalendarLinks.reminder(id: "ABC-123")?.absoluteString == "x-apple-reminderkit://REMCDReminder/ABC-123")
        #expect(CalendarLinks.reminder(id: "") == nil)
    }
}
