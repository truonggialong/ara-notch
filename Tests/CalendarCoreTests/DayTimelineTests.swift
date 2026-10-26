import Foundation
import Testing
@testable import CalendarCore

@Suite struct DayTimelineTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> AgendaEvent {
        AgendaEvent(id: title, title: title, start: start, end: end, isAllDay: allDay, calendarName: "", location: nil)
    }

    private func reminder(_ title: String, due: Date?, hasTime: Bool = true) -> AgendaReminder {
        AgendaReminder(id: title, title: title, due: due, dueHasTime: hasTime, isCompleted: false, listName: "")
    }

    @Test func eventsBecomeRowsWithTheirHoursOfTheDay() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [event("Họp", at(12, 10), at(12, 11, 30))], reminders: [],
            now: at(12, 8), calendar: calendar)
        #expect(timeline.rows.count == 1)
        #expect(timeline.rows[0].kind == .event)
        #expect(timeline.rows[0].start == 10)
        #expect(timeline.rows[0].end == 11.5)
    }

    @Test func rowsRunFromAllDayThroughTheDayThenReminders() {
        let timeline = DayTimeline(
            day: at(12, 0),
            events: [
                event("Chiều", at(12, 15), at(12, 16)), event("Sinh nhật", at(12, 0), at(13, 0), allDay: true),
                event("Sáng", at(12, 9), at(12, 10)),
            ],
            reminders: [
                reminder("Không hạn", due: nil), reminder("Quá hạn", due: at(11, 13)),
                reminder("14 giờ", due: at(12, 14)), reminder("Trong ngày", due: at(12, 0), hasTime: false),
            ],
            now: at(12, 8), calendar: calendar)
        #expect(timeline.rows.map(\.title) == ["Sinh nhật", "Sáng", "Chiều", "14 giờ", "Quá hạn", "Trong ngày", "Không hạn"])
        #expect(timeline.rows[0].isAllDay)
        #expect(timeline.rows[3].start == 14 && timeline.rows[3].end == nil)
        #expect(timeline.rows[4].isOverdue && timeline.rows[4].start == nil)
        #expect(timeline.rows[6].start == nil)
    }

    @Test func rowsWithNoTimeAreKeptApartAndSetTwoAbreast() {
        let timeline = DayTimeline(
            day: at(12, 0),
            events: [event("Sáng", at(12, 9), at(12, 10)), event("Sinh nhật", at(12, 0), at(13, 0), allDay: true)],
            reminders: [
                reminder("a", due: nil), reminder("b", due: nil), reminder("c", due: nil),
                reminder("Quá hạn", due: at(11, 13)), reminder("14 giờ", due: at(12, 14)),
            ],
            now: at(12, 8), calendar: calendar)
        #expect(timeline.timedRows.map(\.title) == ["Sinh nhật", "Sáng", "14 giờ"])
        #expect(timeline.overdueRows.map(\.title) == ["Quá hạn"])
        #expect(timeline.untimedRows.map(\.title) == ["a", "b", "c"])
        // Three rows across the hours; a heading and one line for the one overdue; a heading
        // and two lines for the three without a time, two abreast.
        #expect(timeline.lineCount == 3 + (1 + 1) + (1 + 2))
    }

    @Test func aDayWithNothingAtASetHourKeepsRoomForItsChart() {
        // Only reminders with no hour: the hours still show, over a little empty room where
        // the first bar will go, and the reminders are listed under it.
        let timeline = DayTimeline(
            day: at(12, 0), events: [], reminders: [reminder("a", due: nil), reminder("Quá hạn", due: at(11, 13))],
            now: at(12, 8), calendar: calendar)
        #expect(timeline.timedRows.isEmpty)
        #expect(timeline.firstHour == 8 && timeline.lastHour == 18)
        #expect(timeline.lineCount == DayTimeline.emptyChartLines + (1 + 1) + (1 + 1))
        #expect(DayTimeline.emptyChartLines == 2)
    }

    @Test func aDayWithNothingLooseHasNoHeadingsForIt() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [event("Sáng", at(12, 9), at(12, 10))], reminders: [], now: at(12, 8),
            calendar: calendar)
        // One row is fewer than the room always kept for the chart.
        #expect(timeline.lineCount == DayTimeline.emptyChartLines)
        #expect(timeline.overdueRows.isEmpty && timeline.untimedRows.isEmpty)
    }

    @Test func aDayThatIsNotTodayShowsOnlyWhatIsDueOnIt() {
        let timeline = DayTimeline(
            day: at(14, 0), events: [],
            reminders: [
                reminder("Không hạn", due: nil), reminder("Quá hạn", due: at(11, 13)), reminder("Ngày 14", due: at(14, 9)),
            ],
            now: at(12, 8), calendar: calendar)
        #expect(timeline.rows.map(\.title) == ["Ngày 14"])
    }

    @Test func anEventRunningOverMidnightIsCutToTheDay() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [event("Đêm", at(11, 22), at(12, 2)), event("Khuya", at(12, 23), at(13, 1))],
            reminders: [], now: at(12, 8), calendar: calendar)
        #expect(timeline.rows[0].start == 0 && timeline.rows[0].end == 2)
        #expect(timeline.rows[1].start == 23 && timeline.rows[1].end == 24)
    }

    @Test func theHoursShownReachALittlePastWhatHappens() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [event("A", at(12, 9, 30), at(12, 10)), event("B", at(12, 20), at(12, 21, 15))],
            reminders: [], now: at(12, 8), calendar: calendar)
        // An hour before the earliest start, an hour after the latest end, on whole hours.
        #expect(timeline.firstHour == 8)
        #expect(timeline.lastHour == 23)
    }

    @Test func aQuietDayShowsTheWorkingHours() {
        let empty = DayTimeline(day: at(12, 0), events: [], reminders: [], now: at(12, 8), calendar: calendar)
        #expect(empty.firstHour == 8 && empty.lastHour == 18)
        // One short meeting: the span is still at least eight hours, kept within the day.
        let one = DayTimeline(
            day: at(12, 0), events: [event("A", at(12, 22), at(12, 23))], reminders: [], now: at(12, 8),
            calendar: calendar)
        #expect(one.lastHour == 24)
        #expect(one.lastHour - one.firstHour == 8)
    }

    @Test func aTimeIsPlacedAcrossTheHoursShown() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [event("A", at(12, 10), at(12, 14))], reminders: [], now: at(12, 8),
            calendar: calendar)
        // Hours 9 to 17 are shown.
        #expect(timeline.firstHour == 9 && timeline.lastHour == 17)
        #expect(timeline.position(ofHour: 9) == 0)
        #expect(timeline.position(ofHour: 13) == 0.5)
        #expect(timeline.position(ofHour: 30) == 1)
        #expect(timeline.hourOf(at(12, 13, 30)) == 13.5)
    }

    @Test func anEstimatedReminderIsABarThatEndsAtItsDueTime() {
        // Due at 10 with two hours of work: the work runs from 8 to 10, the due time is its deadline.
        let timeline = DayTimeline(
            day: at(12, 0), events: [],
            reminders: [reminder("Lắp", due: at(12, 10)), reminder("Mua", due: at(12, 15))],
            estimates: ["Lắp": 120], now: at(12, 6), calendar: calendar)
        let fitted = timeline.rows.first { $0.id == "Lắp" }!
        #expect(fitted.start == 10)
        #expect(fitted.workStart == 8)
        #expect(timeline.rows.first { $0.id == "Mua" }!.workStart == nil)
        // The chart begins an hour before the work does, not before the due time.
        #expect(timeline.firstHour == 7)
    }

    @Test func workThatWouldBeginTheDayBeforeBeginsWithTheDay() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [], reminders: [reminder("Sớm", due: at(12, 0, 30))],
            estimates: ["Sớm": 120], now: at(12, 6), calendar: calendar)
        #expect(timeline.rows[0].workStart == 0)
    }

    @Test func aReminderAtNoHourHasNoBarWhateverItsEstimate() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [], reminders: [reminder("Trong ngày", due: at(12, 0), hasTime: false)],
            estimates: ["Trong ngày": 60], now: at(12, 6), calendar: calendar)
        #expect(timeline.rows[0].workStart == nil)
        #expect(timeline.timedRows.isEmpty)
    }

    private func editing(_ title: String, due: Date?, hasTime: Bool = true, estimate: Int?) -> ReminderDetail {
        ReminderDetail(
            id: title, title: title, notes: "", due: due, dueHasTime: hasTime, repeats: .never, alertMinutes: nil,
            priority: .none, listID: "", estimateMinutes: estimate)
    }

    private func preview(_ detail: ReminderDetail?, reminders: [AgendaReminder], estimates: [String: Int] = [:]) -> DayTimeline {
        DayTimeline.previewing(
            detail, day: at(12, 0), events: [], reminders: reminders, estimates: estimates, now: at(12, 6),
            calendar: calendar)
    }

    @Test func anEstimateBeingChosenShowsOnTheChartBeforeItIsSaved() {
        let reminders = [reminder("Lắp", due: at(12, 10))]
        // Nothing saved yet; two hours chosen in the editor.
        let chosen = preview(editing("Lắp", due: at(12, 10), estimate: 120), reminders: reminders)
        #expect(chosen.rows[0].workStart == 8)
        // Chosen away again in the editor, though one is saved: the bar goes at once.
        let cleared = preview(editing("Lắp", due: at(12, 10), estimate: nil), reminders: reminders, estimates: ["Lắp": 60])
        #expect(cleared.rows[0].workStart == nil)
        // With no editor open the saved ones show.
        #expect(preview(nil, reminders: reminders, estimates: ["Lắp": 60]).rows[0].workStart == 9)
    }

    @Test func aTimeBeingChosenMovesTheReminderOnTheChartBeforeItIsSaved() {
        // Saved with no hour; in the editor it has 15:00 and an hour of work.
        let reminders = [reminder("Mua", due: at(12, 0), hasTime: false)]
        let timeline = preview(editing("Mua", due: at(12, 15), estimate: 60), reminders: reminders)
        #expect(timeline.timedRows.map(\.id) == ["Mua"])
        #expect(timeline.rows[0].start == 15)
        #expect(timeline.rows[0].workStart == 14)
    }

    @Test func aDayBeingChosenThatWouldTakeTheRowAwayLeavesItWhereItIs() {
        // The editor stands under the row: moved to the 16th in it, the row stays on the
        // 12th until Done, and the estimate shows against the time it still has there.
        let reminders = [reminder("Lắp", due: at(12, 10))]
        let timeline = preview(editing("Lắp", due: at(16, 9), estimate: 120), reminders: reminders)
        #expect(timeline.rows.map(\.id) == ["Lắp"])
        #expect(timeline.rows[0].start == 10)
        #expect(timeline.rows[0].workStart == 8)
    }


    private func done(_ title: String, at completed: Date, due: Date? = nil) -> AgendaReminder {
        AgendaReminder(id: title, title: title, due: due, isCompleted: true, listName: "", completedAt: completed)
    }

    @Test func remindersFinishedOnTheDayAreAGroupOfTheirOwnLatestFirst() {
        let timeline = DayTimeline(
            day: at(12, 0), events: [], reminders: [reminder("Mua", due: nil)],
            completed: [
                done("Sáng", at: at(12, 9, 40)), done("Chiều", at: at(12, 14, 2), due: at(12, 10)),
                done("Hôm qua", at: at(11, 20)), done("Ngày mai", at: at(13, 8)),
            ],
            now: at(12, 16), calendar: calendar)
        #expect(timeline.doneRows.map(\.id) == ["Chiều", "Sáng"])
        #expect(timeline.doneRows.map(\.isDone) == [true, true])
        // Finished, they have no place across the hours and are not among the open ones.
        #expect(timeline.timedRows.isEmpty)
        #expect(timeline.untimedRows.map(\.id) == ["Mua"])
        #expect(timeline.overdueRows.isEmpty)
    }

    @Test func theFinishedGroupTakesItsLinesOfThePage() {
        let open = DayTimeline(day: at(12, 0), events: [], reminders: [], now: at(12, 16), calendar: calendar)
        let withDone = DayTimeline(
            day: at(12, 0), events: [], reminders: [],
            completed: [done("A", at: at(12, 9)), done("B", at: at(12, 10)), done("C", at: at(12, 11))],
            now: at(12, 16), calendar: calendar)
        // A heading and three rows set two abreast.
        #expect(withDone.lineCount == open.lineCount + 3)
    }

}

@Suite struct CalendarPageHeightTests {
    private func day(_ items: Int) -> UpcomingDay {
        UpcomingDay(
            day: Date(timeIntervalSince1970: 1_792_000_000),
            items: (0..<items).map {
                UpcomingItem(kind: .event, sourceID: "e\($0)", title: "e", time: nil, tint: nil)
            })
    }

    @Test func thePageGrowsWithItsRows() {
        // Room for the month on the left at the least; then a row's height for each row.
        #expect(CalendarPageHeight.sheetHeight(rows: 0) >= CalendarPageHeight.minimumSheetHeight)
        let ten = CalendarPageHeight.sheetHeight(rows: 10)
        let eleven = CalendarPageHeight.sheetHeight(rows: 11)
        #expect(eleven - ten == CalendarPageHeight.rowHeight)
        #expect(ten > CalendarPageHeight.minimumSheetHeight)
    }

    @Test func theNextDaysUnderTheMonthMakeThePageTallerWhenTheyNeedMoreThanTheDay() {
        // Nothing ahead: the month, its line and the heading with the line saying so.
        let none = CalendarPageHeight.sheetHeight(rows: 0, upcoming: [])
        #expect(none == CalendarPageHeight.minimumSheetHeight + CalendarPageHeight.upcomingHeight([]))
        #expect(CalendarPageHeight.upcomingHeight([]) == 8 + 16 + 16)
        // Each day ahead: its name, and a line for each thing on it.
        #expect(CalendarPageHeight.upcomingHeight([day(2), day(1)]) == 8 + 16 + (20 + 32) + (20 + 16))
        let busy = [day(4), day(4), day(4)]
        #expect(CalendarPageHeight.sheetHeight(rows: 0, upcoming: busy)
            == CalendarPageHeight.minimumSheetHeight + CalendarPageHeight.upcomingHeight(busy))
        // A day with many rows is taller than the left column: the rows decide.
        let tall = CalendarPageHeight.sheetHeight(rows: 30, upcoming: [day(1)])
        #expect(tall == CalendarPageHeight.sheetHeight(rows: 30))
    }

    @Test func estimatesAreKeptByReminder() {
        let defaults = InMemoryDefaults()
        let store = CalendarSettingsStore(defaults: defaults)
        #expect(store.estimates.isEmpty)
        store.estimates = ["a": 30, "b": 480]
        #expect(CalendarSettingsStore(defaults: defaults).estimates == ["a": 30, "b": 480])
    }
}
