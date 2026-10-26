import Foundation
import Testing
@testable import CalendarCore

@Suite struct ReminderDetailTests {
    private func detail(due: Date? = Date(timeIntervalSince1970: 1_792_000_000)) -> ReminderDetail {
        ReminderDetail(
            id: "r1", title: "Gửi báo cáo", notes: "", due: due, dueHasTime: true, repeats: .weekly, alertMinutes: 30,
            priority: .high, listID: "work")
    }

    @Test func priorityIsReadFromTheSystemsNumbersAndWrittenBack() {
        // The system keeps 0 for none, 1 to 4 for high, 5 for medium, 6 to 9 for low.
        #expect(ReminderPriority(systemValue: 0) == .none)
        #expect(ReminderPriority(systemValue: 1) == .high)
        #expect(ReminderPriority(systemValue: 4) == .high)
        #expect(ReminderPriority(systemValue: 5) == .medium)
        #expect(ReminderPriority(systemValue: 9) == .low)
        #expect(ReminderPriority(systemValue: 42) == .none)
        #expect(ReminderPriority.allCases.map(\.systemValue) == [0, 9, 5, 1])
    }

    @Test func aReminderWithNoDueDayCannotRepeatOrAlertEarly() {
        var edited = detail()
        edited.due = nil
        let saved = edited.normalized
        #expect(saved.repeats == .never)
        #expect(saved.alertMinutes == nil)
        #expect(saved.dueHasTime == false)
    }

    @Test func aReminderDueOnADayAtNoHourKeepsItsRepeatButNotAnEarlyAlert() {
        var edited = detail()
        edited.dueHasTime = false
        let saved = edited.normalized
        #expect(saved.repeats == .weekly)
        #expect(saved.alertMinutes == nil)
    }

    @Test func theTitleIsTrimmedAndAnEmptyOneIsNotSaved() {
        var edited = detail()
        edited.title = "  Gọi lại  "
        edited.notes = "  ghi chú \n"
        #expect(edited.normalized.title == "Gọi lại")
        #expect(edited.normalized.notes == "ghi chú")
        #expect(edited.canSave)
        edited.title = "   "
        #expect(!edited.canSave)
    }

    @Test func settingADayOnAReminderWithoutOneGivesItThatDayAtTheHourOffered() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        var edited = detail(due: nil)
        edited.dueHasTime = false
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 8))!
        edited.setDay(day, newMinutesOfDay: 23 * 60, calendar: calendar)
        // An hour at once, so that an estimate can be chosen without another step.
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: edited.due!)
            == DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 0))
        #expect(edited.dueHasTime)
    }

    @Test func settingADayKeepsAReminderAtNoHourAtNoHourAndATimedOneAtItsHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 8))!
        var allDay = detail(due: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!)
        allDay.dueHasTime = false
        allDay.setDay(day, newMinutesOfDay: 23 * 60, calendar: calendar)
        #expect(allDay.due == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        #expect(!allDay.dueHasTime)
        var timed = detail(due: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9, minute: 30))!)
        timed.setDay(day, newMinutesOfDay: 23 * 60, calendar: calendar)
        #expect(timed.due == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 30)))
        #expect(timed.dueHasTime)
    }

    @Test func settingAnHourKeepsTheDayAndMakesItATimedReminder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        var edited = detail(due: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!)
        edited.setMinutesOfDay(14 * 60 + 30, today: Date(), calendar: calendar)
        #expect(calendar.dateComponents([.year, .month, .day, .hour, .minute], from: edited.due!)
            == DateComponents(year: 2026, month: 10, day: 16, hour: 14, minute: 30))
        #expect(edited.dueHasTime)
        // With no day yet, the hour is of today.
        var fresh = detail(due: nil)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8))!
        fresh.setMinutesOfDay(600, today: today, calendar: calendar)
        #expect(calendar.component(.day, from: fresh.due!) == 12)
        #expect(calendar.component(.hour, from: fresh.due!) == 10)
    }

    @Test func droppingTheHourKeepsTheDayAndWithNoDayTakesToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 8))!
        var timed = detail(due: calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9))!)
        timed.setAllDay(today: today, calendar: calendar)
        #expect(timed.dueHasTime == false)
        #expect(timed.due == calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        var fresh = detail(due: nil)
        fresh.dueHasTime = false
        fresh.setAllDay(today: today, calendar: calendar)
        #expect(fresh.dueHasTime == false)
        #expect(fresh.due == calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
    }

    @Test func onlyWhatWasChangedIsWrittenBack() {
        let original = detail()
        #expect(original.changes(from: original).isEmpty)
        var renamed = original
        renamed.title = "  Gửi báo cáo tháng "
        renamed.priority = .low
        #expect(renamed.normalized.changes(from: original) == [.title, .priority])
        // Spaces round a name are not a change.
        var spaced = original
        spaced.title = " Gửi báo cáo "
        #expect(spaced.normalized.changes(from: original).isEmpty)
        var moved = original
        moved.due = original.due!.addingTimeInterval(3_600)
        moved.repeats = .never
        moved.listID = "home"
        #expect(moved.changes(from: original) == [.due, .repeats, .list])
        // An hour dropped is a change of the due date, and takes the early alert with it.
        var wholeDay = original
        wholeDay.dueHasTime = false
        #expect(wholeDay.normalized.changes(from: original) == [.due, .alert])
    }

    @Test func theEarlyAlertIsReadFromTheAlarmsBeforeTheDueTime() {
        let due = Date(timeIntervalSince1970: 1_792_000_000)
        // An alarm at a moment: a quarter of an hour before. The one at the due time is not early.
        #expect(ReminderDetail.earlyMinutes(due: due, alarmDates: [due, due.addingTimeInterval(-900)], offsets: []) == 15)
        // An alarm set as a distance from the due time.
        #expect(ReminderDetail.earlyMinutes(due: due, alarmDates: [], offsets: [0, -1_800]) == 30)
        // Of several, the one nearest the due time.
        #expect(ReminderDetail.earlyMinutes(due: due, alarmDates: [due.addingTimeInterval(-86_400)], offsets: [-300]) == 5)
        #expect(ReminderDetail.earlyMinutes(due: due, alarmDates: [due, due.addingTimeInterval(600)], offsets: [0, 120]) == nil)
        // Without a due time a moment is early for nothing; a distance still counts.
        #expect(ReminderDetail.earlyMinutes(due: nil, alarmDates: [due], offsets: []) == nil)
    }

    @Test func theChoicesOfferedAreTheUsualOnes() {
        #expect(ReminderRepeat.allCases == [.never, .daily, .weekly, .monthly, .yearly])
        // No early alert, then minutes before: five, a quarter and half an hour, an hour, a day.
        #expect(ReminderDetail.alertChoices == [nil, 5, 15, 30, 60, 1_440])
    }

    @Test func anEditorTakesItsOwnRoomOnThePage() {
        // The title, the notes, the row of chips and the buttons, with the card's margins;
        // one more row of chips while the choices of one are on show.
        #expect(ReminderEditorLayout.height(isChoosing: false) == 116)
        #expect(ReminderEditorLayout.height(isChoosing: true) == 144)
    }

    @Test func thePageGrowsByTheRoomOfAnEditor() {
        let plain = CalendarPageHeight.sheetHeight(rows: 10)
        #expect(CalendarPageHeight.sheetHeight(rows: 10, extra: 116) == plain + 116)
    }

    @Test func theEstimatesOfferedRunFromHalfAnHourToAWorkingDay() {
        #expect(ReminderDetail.estimateChoices == [nil, 30, 60, 120, 180, 240, 480])
    }

    @Test func anEstimateNeedsAnHourToEndAtAndIsAChangeLikeAnyOther() {
        var edited = detail()
        edited.estimateMinutes = 120
        #expect(edited.changes(from: detail()) == [.estimate])
        #expect(edited.normalized.estimateMinutes == 120)
        // Without an hour there is nowhere across the day to draw the work.
        edited.dueHasTime = false
        #expect(edited.normalized.estimateMinutes == nil)
    }
}
