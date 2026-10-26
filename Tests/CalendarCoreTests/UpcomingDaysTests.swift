import Foundation
import Testing
@testable import CalendarCore

@Suite struct UpcomingDaysTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ id: String, from start: Date, to end: Date, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, calendarName: "", location: nil)
    }

    private func reminder(_ id: String, due: Date?, hasTime: Bool = true, done: Bool = false) -> AgendaReminder {
        AgendaReminder(id: id, title: id, due: due, dueHasTime: hasTime, isCompleted: done, listName: "")
    }

    @Test func theThreeDaysAfterTodayAreListedAndTheRestLeftOut() {
        let now = at(15, 11)
        let days = UpcomingDays.days(
            events: [
                event("today", from: at(15, 14), to: at(15, 15)),
                event("tomorrow", from: at(16, 9, 30), to: at(16, 10)),
                event("third", from: at(18, 8), to: at(18, 9)),
                event("fourth", from: at(19, 8), to: at(19, 9)),
            ],
            reminders: [reminder("dayAfter", due: at(17, 14))], now: now, calendar: calendar)
        #expect(days.map(\.day) == [at(16), at(17), at(18)])
        #expect(days.map { $0.items.map(\.sourceID) } == [["tomorrow"], ["dayAfter"], ["third"]])
        #expect(days[0].items[0].time == at(16, 9, 30))
        #expect(days[1].items[0].kind == .reminder)
    }

    @Test func aDayWithNothingIsNotListed() {
        let days = UpcomingDays.days(
            events: [event("third", from: at(18, 8), to: at(18, 9))], reminders: [], now: at(15, 11),
            calendar: calendar)
        #expect(days.map(\.day) == [at(18)])
        #expect(UpcomingDays.days(events: [], reminders: [], now: at(15, 11), calendar: calendar).isEmpty)
    }

    @Test func wholeDayItemsComeFirstThenTheRestByTime() {
        let days = UpcomingDays.days(
            events: [
                event("late", from: at(16, 17), to: at(16, 18)),
                event("birthday", from: at(16), to: at(17), allDay: true),
            ],
            reminders: [
                reminder("noon", due: at(16, 12)),
                reminder("someTime", due: at(16), hasTime: false),
            ],
            now: at(15, 11), calendar: calendar)
        #expect(days[0].items.map(\.sourceID) == ["birthday", "someTime", "noon", "late"])
        #expect(days[0].items[0].time == nil)
        #expect(days[0].items[1].time == nil)
    }

    @Test func anEventOverSeveralDaysIsOnEachAndHasItsHourOnlyOnTheFirst() {
        let days = UpcomingDays.days(
            events: [event("trip", from: at(16, 20), to: at(18, 10))], reminders: [], now: at(15, 11),
            calendar: calendar)
        #expect(days.map(\.day) == [at(16), at(17), at(18)])
        #expect(days.map { $0.items[0].time } == [at(16, 20), nil, nil])
        // An event that ends at midnight does not reach into the day that starts then.
        let evening = UpcomingDays.days(
            events: [event("party", from: at(16, 20), to: at(17))], reminders: [], now: at(15, 11),
            calendar: calendar)
        #expect(evening.map(\.day) == [at(16)])
    }

    @Test func finishedAndUndatedRemindersAreLeftOut() {
        let days = UpcomingDays.days(
            events: [],
            reminders: [
                reminder("done", due: at(16, 9), done: true),
                reminder("undated", due: nil),
                reminder("overdue", due: at(14, 9)),
            ],
            now: at(15, 11), calendar: calendar)
        #expect(days.isEmpty)
    }

    @Test func itemsKeepTheirCalendarColourAndCanBeToldApart() {
        var meeting = event("same", from: at(16, 9), to: at(16, 10))
        meeting.tint = 0x0A84FF
        let days = UpcomingDays.days(
            events: [meeting], reminders: [reminder("same", due: at(16, 9))], now: at(15, 11), calendar: calendar)
        #expect(days[0].items.map(\.tint) == [0x0A84FF, nil])
        #expect(Set(days[0].items.map(\.id)).count == 2)
    }
}
