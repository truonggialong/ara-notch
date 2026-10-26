import Foundation
import Testing
@testable import CalendarCore

@Suite struct WeekStripTests {
    private var mondayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        mondayFirst.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func theSevenDaysOfTheWeekADateIsIn() {
        // 12 October 2026 is a Monday.
        let days = WeekStrip.days(around: day(2026, 10, 14), calendar: mondayFirst)
        #expect(days.count == 7)
        #expect(days.map { mondayFirst.component(.day, from: $0) } == [12, 13, 14, 15, 16, 17, 18])
    }

    @Test func aWeekThatCrossesAMonthKeepsItsSevenDays() {
        let days = WeekStrip.days(around: day(2026, 10, 1), calendar: mondayFirst)
        #expect(days.map { mondayFirst.component(.day, from: $0) } == [28, 29, 30, 1, 2, 3, 4])
    }

    @Test func aSundayFirstCalendarStartsOnSunday() {
        var calendar = mondayFirst
        calendar.firstWeekday = 1
        let days = WeekStrip.days(around: day(2026, 10, 14), calendar: calendar)
        #expect(days.map { calendar.component(.day, from: $0) } == [11, 12, 13, 14, 15, 16, 17])
    }
}

@Suite struct LunarDateTests {
    private func noon(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @Test func lunarNewYearIsTheFirstOfTheFirstMonth() {
        #expect(LunarDate(noon(2026, 2, 17)) == LunarDate(day: 1, month: 1, isLeapMonth: false))
        #expect(LunarDate(noon(2025, 1, 29)) == LunarDate(day: 1, month: 1, isLeapMonth: false))
    }

    @Test func midAutumnIsTheFifteenthOfTheEighthMonth() {
        #expect(LunarDate(noon(2025, 10, 6)) == LunarDate(day: 15, month: 8, isLeapMonth: false))
    }

    @Test func aLeapMonthIsMarked() {
        // 2025 repeats its sixth month.
        #expect(LunarDate(noon(2025, 8, 1)) == LunarDate(day: 8, month: 6, isLeapMonth: true))
    }

    @Test func isWrittenDayThenMonth() {
        #expect(LunarDate(day: 16, month: 8, isLeapMonth: false).text == "16/8")
        #expect(LunarDate(day: 8, month: 6, isLeapMonth: true).text == "8/6+")
    }

    @Test func isShownByDefaultOnlyWhereTheLunarCalendarIsUsed() {
        #expect(CalendarSettingsStore.lunarByDefault(languages: ["vi-VN", "en-US"]))
        #expect(CalendarSettingsStore.lunarByDefault(languages: ["zh-Hans-CN"]))
        #expect(!CalendarSettingsStore.lunarByDefault(languages: ["en-US", "vi-VN"]))
        #expect(!CalendarSettingsStore.lunarByDefault(languages: []))
    }

    @Test func theChoiceIsRemembered() {
        let defaults = InMemoryDefaults()
        let store = CalendarSettingsStore(defaults: defaults)
        store.showsLunarDate = true
        #expect(CalendarSettingsStore(defaults: defaults).showsLunarDate == true)
        store.showsLunarDate = false
        #expect(CalendarSettingsStore(defaults: defaults).showsLunarDate == false)
    }
}
