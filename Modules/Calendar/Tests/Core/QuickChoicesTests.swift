import Foundation
import Testing
@testable import CalendarCore

@Suite struct QuickChoicesTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func days(on today: Date) -> [String] {
        QuickDay.choices(today: today, calendar: calendar).map {
            "\($0.kind.rawValue) \(calendar.component(.day, from: $0.day))"
        }
    }

    @Test func onAMondayAllFiveDaysAreOffered() {
        // Monday 12 October 2026, in the afternoon: each choice is the start of its day.
        let choices = QuickDay.choices(today: day(12, hour: 15), calendar: calendar)
        #expect(choices.map(\.kind) == [.today, .tomorrow, .dayAfter, .saturday, .nextWeek])
        #expect(choices.map(\.day) == [day(12), day(13), day(14), day(17), day(19)])
    }

    @Test func aSaturdayThatOneOfTheFirstThreeAlreadyIsIsLeftOut() {
        // Thursday, Friday: Saturday is the day after tomorrow, or tomorrow.
        #expect(days(on: day(15)) == ["today 15", "tomorrow 16", "dayAfter 17", "nextWeek 22"])
        #expect(days(on: day(16)) == ["today 16", "tomorrow 17", "dayAfter 18", "nextWeek 23"])
    }

    @Test func onASaturdayTheNextOneIsThisDayNextWeek() {
        #expect(days(on: day(17)) == ["today 17", "tomorrow 18", "dayAfter 19", "nextWeek 24"])
    }

    @Test func onASundayTheSaturdayAheadIsOffered() {
        #expect(days(on: day(18)) == ["today 18", "tomorrow 19", "dayAfter 20", "saturday 24", "nextWeek 25"])
    }

    @Test func theHoursOfferedAreMorningNoonAfternoonAndEvening() {
        #expect(QuickDay.minutesOfDay == [9 * 60, 12 * 60, 15 * 60, 19 * 60])
    }

    @Test func aPickerNeedsMoreRoomThanTheLeastPage() {
        // The quick days stand under the month in two rows: more than the least page has.
        #expect(CalendarPageHeight.pickerSheetHeight > CalendarPageHeight.minimumSheetHeight)
        #expect(CalendarPageHeight.sheetHeight(rows: 14, extra: 116, isPicking: true) == CalendarPageHeight.pickerSheetHeight)
    }
}
