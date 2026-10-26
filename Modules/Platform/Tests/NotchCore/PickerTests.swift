import Foundation
import Testing
@testable import NotchCore

@Suite struct ClockDialTests {
    @Test func anAngleIsMeasuredClockwiseFromTwelve() {
        #expect(abs(ClockDial.angle(dx: 0, dy: -10) - 0) < 0.001)
        #expect(abs(ClockDial.angle(dx: 10, dy: 0) - 90) < 0.001)
        #expect(abs(ClockDial.angle(dx: 0, dy: 10) - 180) < 0.001)
        #expect(abs(ClockDial.angle(dx: -10, dy: 0) - 270) < 0.001)
    }

    @Test func theOuterRingHoldsTheHoursOfTheFirstHalfOfTheDayFromOne() {
        // Twelve sits at the top of the outer ring, as on a wall clock.
        #expect(ClockDial.hour(angle: 0, isInner: false) == 12)
        #expect(ClockDial.hour(angle: 30, isInner: false) == 1)
        #expect(ClockDial.hour(angle: 270, isInner: false) == 9)
        #expect(ClockDial.hour(angle: 359, isInner: false) == 12)
    }

    @Test func theInnerRingHoldsTheAfternoonAndMidnight() {
        #expect(ClockDial.hour(angle: 0, isInner: true) == 0)
        #expect(ClockDial.hour(angle: 60, isInner: true) == 14)
        #expect(ClockDial.hour(angle: 330, isInner: true) == 23)
        // Half way between two numbers the nearer one wins.
        #expect(ClockDial.hour(angle: 44, isInner: true) == 13)
        #expect(ClockDial.hour(angle: 46, isInner: true) == 14)
    }

    @Test func everyHourHasItsPlaceAndIsFoundThereAgain() {
        for hour in 0..<24 {
            let place = ClockDial.place(ofHour: hour)
            #expect(ClockDial.hour(angle: place.angle, isInner: place.isInner) == hour)
        }
        #expect(ClockDial.place(ofHour: 12).isInner == false)
        #expect(ClockDial.place(ofHour: 0).isInner == true)
        #expect(ClockDial.place(ofHour: 15).angle == 90)
    }

    @Test func aPointNearTheCentreIsOnTheInnerRing() {
        #expect(ClockDial.isInner(distance: 40, radius: 70))
        #expect(!ClockDial.isInner(distance: 60, radius: 70))
    }

    @Test func minutesGoRoundOnceToTheNearestMinute() {
        #expect(ClockDial.minute(angle: 0) == 0)
        #expect(ClockDial.minute(angle: 90) == 15)
        #expect(ClockDial.minute(angle: 182) == 30)
        #expect(ClockDial.minute(angle: 186) == 31)
        #expect(ClockDial.minute(angle: 358) == 0)
        #expect(ClockDial.angle(ofMinute: 45) == 270)
    }

    @Test func theHoursOfALengthAreFourPlacesOnTheInnerRing() {
        #expect(ClockDial.lengthHour(angle: 0) == 0)
        #expect(ClockDial.lengthHour(angle: 100) == 1)
        #expect(ClockDial.lengthHour(angle: 170) == 2)
        #expect(ClockDial.lengthHour(angle: 280) == 3)
        #expect(ClockDial.lengthHour(angle: 340) == 0)
        #expect(ClockDial.angle(ofLengthHour: 3) == 270)
    }

    @Test func aTimeOfDayIsWrittenWithTwoDigitsEach() {
        #expect(ClockDial.text(minutesOfDay: 14 * 60 + 5) == "14:05")
        #expect(ClockDial.text(minutesOfDay: 0) == "00:00")
        #expect(ClockDial.minutesOfDay(hour: 23, minute: 59) == 1_439)
    }
}

@Suite struct MonthGridTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func aMonthIsLaidOutInWeeksFromTheCalendarsFirstWeekday() {
        // October 2026 starts on a Thursday; with weeks from Monday three places are empty.
        let grid = MonthGrid(containing: day(2026, 10, 12), calendar: calendar)
        #expect(grid.month == day(2026, 10, 1))
        #expect(grid.weeks.count == 5)
        #expect(grid.weeks[0] == [nil, nil, nil, day(2026, 10, 1), day(2026, 10, 2), day(2026, 10, 3), day(2026, 10, 4)])
        #expect(grid.weeks[4][6] == nil)
        #expect(grid.weeks[4][5] == day(2026, 10, 31))
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
    }

    @Test func weeksFromSundayShiftTheSameMonth() {
        var sunday = calendar
        sunday.firstWeekday = 1
        let grid = MonthGrid(containing: day(2026, 10, 12), calendar: sunday)
        #expect(grid.weeks[0].firstIndex(of: day(2026, 10, 1)) == 4)
    }

    @Test func aMonthThatNeedsSixWeeksGetsThem() {
        // August 2026 starts on a Saturday and has 31 days.
        #expect(MonthGrid(containing: day(2026, 8, 15), calendar: calendar).weeks.count == 6)
        // February 2027 starts on a Monday and has 28 days.
        #expect(MonthGrid(containing: day(2027, 2, 1), calendar: calendar).weeks.count == 4)
    }

    @Test func goingToAnotherMonthLandsOnItsFirstDay() {
        #expect(MonthGrid.shifting(day(2026, 10, 31), months: 1, calendar: calendar) == day(2026, 11, 1))
        #expect(MonthGrid.shifting(day(2026, 1, 15), months: -1, calendar: calendar) == day(2025, 12, 1))
    }

    @Test func aDayAndATimeOfDayMakeAMoment() {
        let moment = MonthGrid.moment(on: day(2026, 10, 15), minutesOfDay: 14 * 60 + 30, calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
            == DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 30))
        #expect(MonthGrid.minutesOfDay(of: moment, calendar: calendar) == 870)
    }
}

@Suite struct RetiredSettingsTests {
    @Test func namesKeptForSuggestionsAndTheOldCalendarSizeAreRemoved() {
        let defaults = InMemoryDefaults()
        for kind in ["event", "reminder", "timer"] {
            defaults.set(["Họp nhóm"], forKey: "recentNames.\(kind)")
        }
        defaults.set("full", forKey: "calendar.pageSize")
        defaults.set("vi", forKey: "shell.language")
        RetiredSettings.remove(from: defaults)
        for key in ["recentNames.event", "recentNames.reminder", "recentNames.timer", "calendar.pageSize"] {
            #expect(defaults.object(forKey: key) == nil)
        }
        // Everything else stays.
        #expect(defaults.string(forKey: "shell.language") == "vi")
    }
}
