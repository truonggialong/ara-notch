import Foundation
import Testing
@testable import CalendarCore

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    return calendar
}

private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour, minute: minute, second: second))!
}

@Suite struct UntilNextTests {
    @Test func nothingNextHasNoChip() {
        #expect(UntilNext.make(next: nil, now: at(10)) == nil)
    }

    @Test func underAnHourCountsMinutes() {
        #expect(UntilNext.make(next: at(14), now: at(13, 20)) == .minutes(40))
    }

    @Test func minutesAreRoundedUpAndSixtyIsAnHour() {
        #expect(UntilNext.make(next: at(14), now: at(13, 0, 30)) == .hours(1))
        #expect(UntilNext.make(next: at(14), now: at(11, 59)) == .hours(2))
    }

    @Test func aStartAlreadyReachedIsNow() {
        #expect(UntilNext.make(next: at(14), now: at(14)) == .now)
        #expect(UntilNext.make(next: at(14), now: at(14, 5)) == .now)
    }
}
