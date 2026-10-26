import Foundation
import Testing
@testable import CalendarCore

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    return calendar
}

private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + day, hour: hour, minute: minute))!
}

private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
    AgendaEvent(id: title, title: title, start: start, end: end, isAllDay: allDay, calendarName: "Việc", location: nil)
}

private func reminder(_ title: String, due: Date?, hasTime: Bool = true) -> AgendaReminder {
    AgendaReminder(id: title, title: title, due: due, dueHasTime: hasTime, isCompleted: false, listName: "Nhắc")
}

@Suite struct DaySummaryTests {
    @Test func countsWhatIsLeftOfTodayAndFindsTheNextStart() {
        let now = at(10)
        let events = [
            event("Sáng", at(8), at(9)),            // over
            event("Họp", at(9, 30), at(10, 30)),    // under way
            event("Chiều", at(14), at(15)),         // next
            event("Lễ", at(0), at(0, day: 1), allDay: true),
            event("Mai", at(9, day: 1), at(10, day: 1)),
        ]
        let reminders = [
            reminder("Gọi điện", due: at(16)), reminder("Mua sữa", due: at(0), hasTime: false),
            reminder("Tuần sau", due: at(9, day: 7)), reminder("Không hạn", due: nil),
        ]
        let summary = DaySummary.make(events: events, reminders: reminders, at: now, calendar: calendar)
        #expect(summary == DaySummary(count: 5, next: at(14), nextTitle: "Chiều"))
    }

    @Test func theNextCanBeAReminder() {
        let summary = DaySummary.make(events: [], reminders: [reminder("Gọi điện", due: at(16))], at: at(10), calendar: calendar)
        #expect(summary == DaySummary(count: 1, next: at(16), nextTitle: "Gọi điện"))
    }

    @Test func aDayWithNothingLeft() {
        let summary = DaySummary.make(events: [event("Sáng", at(8), at(9))], reminders: [], at: at(10), calendar: calendar)
        #expect(summary == DaySummary(count: 0, next: nil))
    }
}

@Suite struct DayListTests {
    @Test func todaysThingsAndTheOverdueAreKeptApart() {
        let now = at(10)
        let list = DayList.make(
            events: [event("Họp", at(14), at(15)), event("Mai", at(9, day: 1), at(10, day: 1))],
            reminders: [
                reminder("Gọi điện", due: at(16)),                        // today
                reminder("Sáng nay", due: at(8)),                          // overdue, earlier today
                reminder("Hôm qua", due: at(0, day: -1), hasTime: false),  // overdue
                reminder("Cả ngày nay", due: at(0), hasTime: false),       // today, not overdue
                reminder("Ngày mai", due: at(9, day: 1)),                  // not today
                reminder("Không hạn", due: nil),                           // no date
            ],
            at: now, calendar: calendar)
        #expect(list.events.map(\.title) == ["Họp"])
        #expect(list.dueToday.map(\.title) == ["Gọi điện", "Cả ngày nay"])
        #expect(list.overdue.map(\.title) == ["Hôm qua", "Sáng nay"])
    }

    @Test func theSummaryCountsTheOverdue() {
        let summary = DaySummary.make(
            events: [], reminders: [reminder("Hôm qua", due: at(0, day: -1), hasTime: false), reminder("Tuần trước", due: at(9, day: -7))],
            at: at(10), calendar: calendar)
        #expect(summary.count == 0)
        #expect(summary.overdue == 2)
    }
}
