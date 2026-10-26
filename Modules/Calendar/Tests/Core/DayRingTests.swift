import Foundation
import Testing
@testable import CalendarCore

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    return calendar
}

/// A time on 12 October 2026 (or `day` days later), local time.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 12 + day, hour: hour, minute: minute))!
}

private func event(_ id: String, _ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
    AgendaEvent(id: id, title: title, start: start, end: end, isAllDay: allDay, calendarName: "Việc", location: nil)
}

@Suite struct DayRingTests {
    @Test func midnightSixNoonAndSixAreQuarters() {
        let day = at(0)
        #expect(DayRing.fraction(of: at(0), on: day, calendar: calendar) == 0)
        #expect(DayRing.fraction(of: at(6), on: day, calendar: calendar) == 0.25)
        #expect(DayRing.fraction(of: at(12), on: day, calendar: calendar) == 0.5)
        #expect(DayRing.fraction(of: at(18), on: day, calendar: calendar) == 0.75)
    }

    @Test func anEventOverMidnightIsCutAtTheEdgesOfTheDay() {
        let day = at(0)
        let late = event("a", "Đêm", at(22, day: -1), at(2))
        let night = event("b", "Khuya", at(23), at(1, day: 1))
        #expect(DayRing.arcs(for: [night, late], on: day, calendar: calendar) == [0...(2.0 / 24), (23.0 / 24)...1])
    }

    @Test func allDayEventsAndOtherDaysHaveNoArc() {
        let day = at(0)
        let holiday = event("c", "Lễ", at(0), at(0, day: 1), allDay: true)
        let tomorrow = event("d", "Mai", at(9, day: 1), at(10, day: 1))
        #expect(DayRing.arcs(for: [holiday, tomorrow], on: day, calendar: calendar).isEmpty)
    }

    @Test func aDayWithAnExtraHourStillEndsAtOne() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        // Summer time ends on 1 November 2026: the day has 25 hours.
        let day = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let noon = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        #expect(abs(DayRing.fraction(of: noon, on: day, calendar: newYork) - 13.0 / 25) < 0.0001)
    }
}
