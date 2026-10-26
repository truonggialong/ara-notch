import CalendarCore
import NotchShell
import SwiftUI

/// The calendar page of the notch: the month on the left and, beside it, the chosen day as
/// a chart of its hours with the reminders that have none listed under it.
struct CalendarPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: CalendarViewModel
    @ObservedObject var settings: CalendarSettings
    @Environment(\.araHue) private var hue

    /// The day the page shows: the one chosen in the week strip, or today.
    private var shownDay: Date {
        model.selectedDay ?? Calendar.current.startOfDay(for: model.now)
    }

    var body: some View {
        Group {
            if let picker = model.picker {
                pickerSheet(picker)
            } else {
                monthAndDay
            }
        }
        // A reminder just ticked off can be taken back from here for a few seconds, and a
        // change that did not go through says why here.
        .overlay(alignment: .bottom) {
            if let notice = model.pageNotice {
                AraSignBanner(sign: notice) { model.onPageNotice?() }
                    .padding(.bottom, 8 * ui)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: model.pageNotice != nil)
        .onAppear { model.onAppear?() }
    }

    // MARK: - Choosing a day and a time by sight

    /// In place of the lists: a month to choose the day from and, for an event or a
    /// reminder, a clock face to choose the time on.
    private func pickerSheet(_ picker: CalendarPicker) -> some View {
        HStack(alignment: .center, spacing: 14 * ui) {
            switch picker {
            case .day:
                monthWithQuickDays(
                    day: Binding(get: { shownDay }, set: { model.onSelectDay?($0) }), selected: shownDay,
                    marked: model.markedDays, onShowMonth: model.onShowMonth, onPick: { model.picker = nil })
                pickerSide(summary: Self.fullDay.string(from: shownDay)) { EmptyView() }
            case .event:
                monthWithQuickDays(
                    day: Binding(get: { model.eventDraft?.day ?? shownDay }, set: { model.eventDraft?.day = $0 }),
                    selected: model.eventDraft?.day ?? shownDay)
                if model.eventDraft?.startMinutes != nil {
                    clockWithQuickHours(Binding(
                        get: { model.eventDraft?.startMinutes ?? 9 * 60 },
                        set: { model.eventDraft?.startMinutes = $0 }))
                }
                pickerSide(summary: eventWhenText) {
                    AraChip(isSelected: model.eventDraft?.startMinutes == nil) {
                        if model.eventDraft?.startMinutes == nil {
                            model.eventDraft?.startMinutes = EventDraft.defaultStartMinutes(
                                on: model.eventDraft?.day ?? shownDay, now: model.now, calendar: .current)
                        } else {
                            model.eventDraft?.startMinutes = nil
                        }
                    } label: {
                        Text(L10n.string("calendar.allDay")).font(.system(size: 11 * ui, weight: .medium))
                    }
                }
            case .editing:
                let due = model.editing?.due ?? Self.defaultDue(now: model.now)
                monthWithQuickDays(
                    day: Binding(
                        get: { Calendar.current.startOfDay(for: due) },
                        set: {
                            model.editing?.setDay(
                                $0, newMinutesOfDay: AraMoment.minutesOfDay(of: Self.defaultDue(now: model.now)),
                                calendar: .current)
                        }),
                    selected: model.editing?.due)
                if model.editing?.dueHasTime == true {
                    clockWithQuickHours(Binding(
                        get: { AraMoment.minutesOfDay(of: due) },
                        set: { model.editing?.setMinutesOfDay($0, today: model.now, calendar: .current) }))
                }
                // Wider than the others: three kinds of due date stand side by side.
                pickerSide(summary: editingDueText(long: true), width: 190) {
                    HStack(spacing: 3 * ui) {
                        // No day at all, a day at no particular hour, or a day and an hour.
                        dueKindChip("calendar.reminder.noDue", isOn: model.editing?.due == nil) {
                            model.editing?.due = nil
                            model.editing?.dueHasTime = false
                        }
                        dueKindChip(
                            "calendar.allDay", isOn: model.editing?.due != nil && model.editing?.dueHasTime == false
                        ) {
                            model.editing?.setAllDay(today: model.now, calendar: .current)
                        }
                        dueKindChip("calendar.reminder.timed", isOn: model.editing?.dueHasTime == true) {
                            guard model.editing?.dueHasTime == false else { return }
                            model.editing?.setMinutesOfDay(
                                AraMoment.minutesOfDay(of: Self.defaultDue(now: model.now)), today: model.now,
                                calendar: .current)
                        }
                    }
                }
            case .reminder:
                let due = model.reminderDue ?? Self.defaultDue(now: model.now)
                monthWithQuickDays(
                    day: Binding(
                        get: { Calendar.current.startOfDay(for: due) },
                        set: { model.reminderDue = AraMoment.moment(on: $0, minutesOfDay: AraMoment.minutesOfDay(of: due)) }),
                    selected: model.reminderDue)
                clockWithQuickHours(Binding(
                    get: { AraMoment.minutesOfDay(of: due) },
                    set: { model.reminderDue = AraMoment.moment(on: due, minutesOfDay: $0) }))
                pickerSide(summary: model.reminderDue.map(Self.dueTitle.string) ?? L10n.string("calendar.reminder.noDue")) {
                    AraChip(isSelected: model.reminderDue == nil) {
                        model.reminderDue = nil
                        model.picker = nil
                    } label: {
                        Text(L10n.string("calendar.reminder.noDue")).font(.system(size: 11 * ui, weight: .medium))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The month to choose a day from, and under it the days asked for most, one click each.
    /// - Parameter selected: the day chosen so far, whose quick choice is filled; nil for none yet.
    private func monthWithQuickDays(
        day: Binding<Date>, selected: Date?, marked: Set<Date> = [], onShowMonth: ((Date) -> Void)? = nil,
        onPick: (() -> Void)? = nil
    ) -> some View {
        let choices = QuickDay.choices(today: model.now, calendar: .current)
        return VStack(alignment: .leading, spacing: 6 * ui) {
            AraMonthCalendar(day: day, today: model.now, marked: marked, onShowMonth: onShowMonth, onPick: onPick)
            VStack(alignment: .leading, spacing: 3 * ui) {
                // Today and the two days after it, then the ones further off with their dates.
                ForEach([Array(choices.prefix(3)), Array(choices.dropFirst(3))], id: \.first?.id) { row in
                    HStack(spacing: 3 * ui) {
                        ForEach(row) { choice in
                            quickChip(
                                L10n.string("calendar.quick.\(choice.kind.rawValue)"),
                                detail: row.first?.kind == .today ? nil : Self.dayNumber.string(from: choice.day),
                                isOn: selected.map { Calendar.current.isDate($0, inSameDayAs: choice.day) } ?? false
                            ) {
                                day.wrappedValue = choice.day
                                onPick?()
                            }
                        }
                    }
                }
            }
        }
    }

    /// The clock to choose a time on, and under it four hours of the day, one click each.
    private func clockWithQuickHours(_ minutesOfDay: Binding<Int>) -> some View {
        VStack(spacing: 6 * ui) {
            AraClockFace(minutesOfDay: minutesOfDay)
            HStack(spacing: 3 * ui) {
                ForEach(QuickDay.minutesOfDay, id: \.self) { minutes in
                    quickChip(Self.clock(minutes), detail: nil, isOn: minutesOfDay.wrappedValue == minutes) {
                        minutesOfDay.wrappedValue = minutes
                    }
                }
            }
        }
    }

    /// A chip of the quick choices: narrower than the usual one, so three stand under the month.
    private func quickChip(_ text: String, detail: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        AraChip(isSelected: isOn, action: action) {
            HStack(spacing: 3 * ui) {
                Text(text).font(.system(size: 10 * ui, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 9 * ui, weight: .medium)).opacity(0.6)
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, -4 * ui)
        }
        .accessibilityLabel(text)
    }

    /// "17": the day of the month beside a quick choice that is some days off.
    private static let dayNumber: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    /// One of the kinds of due date a reminder may have, the present one filled.
    private func dueKindChip(_ key: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        quickChip(L10n.string(key), detail: nil, isOn: isOn, action: action)
    }

    /// Beside the month and the clock: what was chosen, in words, an extra choice, and the
    /// button back to the page.
    private func pickerSide<Extra: View>(
        summary: String, width: CGFloat = 150, @ViewBuilder extra: () -> Extra
    ) -> some View {
        VStack(alignment: .leading, spacing: 8 * ui) {
            Text(summary)
                .font(AraType.display(14 * ui))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            extra()
            AraPillButton(L10n.string("picker.done"), icon: .confirm, isProminent: true) { model.picker = nil }
        }
        .frame(width: width * ui, alignment: .leading)
    }

    private var eventWhenText: String {
        guard let draft = model.eventDraft else { return "" }
        let day = Self.dayTitle.string(from: draft.day)
        return draft.startMinutes.map { "\(day) · \(Self.clock($0))" } ?? "\(day) · \(L10n.string("calendar.allDay"))"
    }

    /// A reminder's time until the user says otherwise: the next full hour.
    private static func defaultDue(now: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
    }

    /// "Thu 15 Oct, 14:30": when a reminder is due.
    private static let dueTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return formatter
    }()

    // MARK: - The month and the day's chart

    private static let labelWidth: CGFloat = 150
    private static let rowHeight = CGFloat(CalendarPageHeight.rowHeight)
    private var upcomingLine: CGFloat { CGFloat(CalendarPageHeight.upcomingLine) * ui }

    /// The roomy page: the month always there on the left, and on the right the day chosen in
    /// it as a chart, hours across and a row for each event and reminder. The notch is as
    /// tall as the rows need.
    private var monthAndDay: some View {
        HStack(alignment: .top, spacing: 12 * ui) {
            VStack(alignment: .leading, spacing: 2 * ui) {
                AraMonthCalendar(
                    day: Binding(get: { shownDay }, set: { model.onSelectDay?($0) }), today: model.now,
                    marked: model.markedDays, onShowMonth: model.onShowMonth)
                    .frame(height: 148 * ui)
                HStack(spacing: 6 * ui) {
                    if settings.showsLunarDate {
                        Text(String(format: L10n.string("calendar.lunar"), LunarDate(shownDay).text))
                            .font(.system(size: 10 * ui, weight: .semibold))
                            .foregroundStyle(AraPalette.label(in: hue))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0 * ui)
                    if model.selectedDay != nil {
                        AraPillButton(L10n.string("calendar.today")) { model.onSelectDay?(model.now) }
                            .scaleEffect(0.86, anchor: .trailing)
                    }
                }
                // Under the month: the next days.
                upcomingList
                    .padding(.top, CGFloat(CalendarPageHeight.upcomingTop) * ui)
                Spacer(minLength: 0 * ui)
            }
            .frame(width: 175 * ui)
            VStack(alignment: .leading, spacing: 4 * ui) {
                dayHeader
                if model.eventAccess != .granted || model.reminderAccess != .granted {
                    accessNotes
                }
                if model.eventDraft != nil {
                    eventDraftRow
                }
                if model.reminderDraft != nil {
                    draftRow
                }
                chart
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - The next days

    /// Under the month: what is on the next days, a line each, under the day's name.
    /// Each part has the height `CalendarPageHeight` counts for it, so the page is as tall as the list.
    private var upcomingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5 * ui) {
                Text(L10n.string("calendar.upcoming"))
                    .font(.system(size: 9.5 * ui, weight: .semibold))
                Rectangle()
                    .fill(AraPalette.hairline)
                    .frame(height: 1 * ui)
            }
            .foregroundStyle(AraTheme.secondaryText)
            .frame(height: upcomingLine)
            if model.upcoming.isEmpty {
                Text(String(format: L10n.string("calendar.upcoming.empty"), UpcomingDays.dayCount))
                    .font(.system(size: 10 * ui))
                    .foregroundStyle(AraTheme.secondaryText)
                    .lineLimit(1)
                    .frame(height: upcomingLine)
            }
            ForEach(model.upcoming) { day in
                Text(upcomingDayTitle(day.day))
                    .font(.system(size: 9.5 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.label(in: hue))
                    .frame(height: CGFloat(CalendarPageHeight.upcomingDayTitle) * ui, alignment: .bottom)
                ForEach(day.items) { item in
                    upcomingRow(item, on: day.day)
                }
            }
        }
    }

    /// "Tomorrow", "In two days", then "Sat 17 Oct".
    private func upcomingDayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: model.now), to: day).day ?? 0
        switch days {
        case 1: return L10n.string("calendar.quick.tomorrow")
        case 2: return L10n.string("calendar.quick.dayAfter")
        default: return Self.dayTitle.string(from: day)
        }
    }

    /// One thing on a day ahead: a click shows that day; the ring of a reminder ticks it off.
    private func upcomingRow(_ item: UpcomingItem, on day: Date) -> some View {
        HStack(spacing: 5 * ui) {
            switch item.kind {
            case .event:
                RoundedRectangle(cornerRadius: 1.5 * ui)
                    .fill(Self.color(item.tint))
                    .frame(width: 3 * ui, height: 11 * ui)
                    .frame(width: 12 * ui)
            case .reminder:
                Button {
                    if let reminder = model.timelineReminders[item.sourceID] {
                        model.onComplete?(reminder)
                    }
                } label: {
                    AraIcon.complete.image
                        .font(.system(size: 10 * ui))
                        .foregroundStyle(AraPalette.ink.opacity(0.55))
                        .frame(width: 12 * ui, height: upcomingLine)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AraPressStyle())
                .help(L10n.string("calendar.reminder.complete"))
            }
            Button {
                model.onSelectDay?(day)
            } label: {
                HStack(spacing: 5 * ui) {
                    Text(item.time.map(Self.time.string) ?? L10n.string("calendar.allDay"))
                        .font(.system(size: 9.5 * ui, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AraTheme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                    Text(item.title)
                        .font(.system(size: 10.5 * ui, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0 * ui)
                }
                .frame(height: upcomingLine)
                .contentShape(Rectangle())
            }
            .buttonStyle(AraPressStyle())
            .help(item.title)
        }
    }

    /// The day on show, with the buttons that add to it and the one that sizes the page.
    private var dayHeader: some View {
        HStack(spacing: 4 * ui) {
            Text(Self.fullDay.string(from: shownDay))
                .font(AraType.display(14 * ui))
                .lineLimit(1)
            Spacer(minLength: 4 * ui)
            if model.reminderAccess == .granted {
                AraIconButton(.remind, look: .bare, size: .small, help: L10n.string("calendar.reminder.add")) {
                    model.reminderDraft = ""
                    model.onBeginReminder?()
                }
            }
            if model.eventAccess == .granted {
                AraIconButton(.add, look: .bare, size: .small, help: L10n.string("calendar.event.add")) {
                    model.onBeginEvent?()
                }
            }
        }
        .frame(height: 24 * ui)
    }

    /// Where the calendars or the reminders may not be read yet: a button to allow each or,
    /// once refused, the way to the system's settings.
    private var accessNotes: some View {
        HStack(spacing: 6 * ui) {
            accessPill(model.eventAccess, ask: "calendar.access.events", refused: "calendar.denied.events", reminders: false) {
                model.onRequestEvents?()
            }
            accessPill(
                model.reminderAccess, ask: "calendar.access.reminders", refused: "calendar.denied.reminders", reminders: true
            ) {
                model.onRequestReminders?()
            }
            Spacer(minLength: 0 * ui)
        }
        .scaleEffect(0.9, anchor: .leading)
    }

    @ViewBuilder
    private func accessPill(
        _ access: AgendaAccess, ask: String, refused: String, reminders: Bool, request: @escaping () -> Void
    ) -> some View {
        switch access {
        case .granted:
            EmptyView()
        case .undetermined:
            AraPillButton(L10n.string(ask), icon: .unlocked, action: request)
        case .denied:
            AraPillButton(L10n.string(refused), icon: .settings) { model.onOpenPrivacySettings?(reminders) }
                .help(L10n.string("calendar.openSettings"))
        }
    }

    /// The hours across the top, then a row for each event and reminder of the day.
    private var chart: some View {
        let timeline = model.timeline
        // The hours are always across the top, with their lines behind the rows that have a
        // place across them, or behind a little empty room on a day when nothing has.
        let chartLines = max(timeline.timedRows.count, DayTimeline.emptyChartLines)
        let timedHeight = CGFloat(chartLines) * (Self.rowHeight * ui)
        return VStack(spacing: 0 * ui) {
            hourAxis(timeline)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0 * ui) {
                    ForEach(timeline.timedRows) { row in
                        chartRow(row, in: timeline)
                        if row.kind == .reminder, model.editing?.id == row.id {
                            editorCard
                        }
                    }
                    if timeline.timedRows.isEmpty {
                        // Nothing at a set hour: the chart's room stays, and says so.
                        Text(L10n.string(timeline.rows.isEmpty
                            ? (model.selectedDay == nil ? "calendar.empty.today.all" : "calendar.empty.day")
                            : "calendar.chart.empty"))
                            .font(.system(size: 10.5 * ui))
                            .foregroundStyle(AraTheme.secondaryText)
                            .padding(.leading, Self.labelWidth * ui)
                            .frame(maxWidth: .infinity)
                            .frame(height: timedHeight)
                    } else if timeline.timedRows.count < chartLines {
                        Color.clear.frame(height: timedHeight - CGFloat(timeline.timedRows.count) * (Self.rowHeight * ui))
                    }
                    // What has no hour has no place across the hours: it is listed
                    // below, two abreast, so it takes half the height.
                    looseRows(timeline.overdueRows, titleKey: "calendar.chart.overdue", isOverdue: true)
                    looseRows(timeline.untimedRows, titleKey: "calendar.chart.anytime", isOverdue: false)
                    // What was finished on this day.
                    looseRows(timeline.doneRows, titleKey: "calendar.chart.done", isOverdue: false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(alignment: .topLeading) {
            GeometryReader { area in
                let track = area.size.width - (Self.labelWidth * ui)
                let height = min(timedHeight, max(area.size.height - 14 * ui, 0))
                if height > 0 {
                    ForEach(Self.ticks(of: timeline), id: \.self) { hour in
                        Rectangle()
                            .fill(AraPalette.hairline.opacity(0.5))
                            .frame(width: 1 * ui, height: height)
                            .offset(x: (Self.labelWidth * ui) + track * timeline.position(ofHour: Double(hour)), y: 14)
                    }
                    if model.selectedDay == nil {
                        let now = timeline.hourOf(model.now)
                        if now >= Double(timeline.firstHour), now <= Double(timeline.lastHour) {
                            Rectangle()
                                .fill(AraPalette.brand)
                                .frame(width: 1.5 * ui, height: height + 2 * ui)
                                .offset(x: (Self.labelWidth * ui) + track * timeline.position(ofHour: now), y: 12)
                        }
                    }
                }
            }
        }
    }

    /// The whole hours that get a line and a number: as many as fit without crowding.
    private static func ticks(of timeline: DayTimeline) -> [Int] {
        let span = timeline.lastHour - timeline.firstHour
        let step = span > 16 ? 3 : span > 9 ? 2 : 1
        return Array(stride(from: timeline.firstHour, through: timeline.lastHour, by: step))
    }

    private func hourAxis(_ timeline: DayTimeline) -> some View {
        GeometryReader { area in
            let track = area.size.width - (Self.labelWidth * ui)
            ForEach(Self.ticks(of: timeline), id: \.self) { hour in
                Text(String(format: "%02d", hour % 24))
                    .font(.system(size: 9 * ui, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AraTheme.secondaryText)
                    .frame(width: 20 * ui)
                    .offset(x: (Self.labelWidth * ui) + track * timeline.position(ofHour: Double(hour)) - 10)
            }
        }
        .frame(height: 14 * ui)
    }

    /// Reminders with no hour, under a heading, two to a line.
    @ViewBuilder
    private func looseRows(_ rows: [DayTimeline.Row], titleKey: String, isOverdue: Bool) -> some View {
        if !rows.isEmpty {
            HStack(spacing: 5 * ui) {
                Text(L10n.string(titleKey))
                    .font(.system(size: 9.5 * ui, weight: .semibold))
                Text(String(rows.count))
                    .font(.system(size: 9.5 * ui, weight: .medium))
                    .monospacedDigit()
                    .opacity(0.7)
                Rectangle()
                    .fill(AraPalette.hairline)
                    .frame(height: 1 * ui)
            }
            .foregroundStyle(isOverdue ? AraPalette.danger : AraTheme.secondaryText)
            .padding(.leading, 3 * ui)
            .frame(height: Self.rowHeight * ui)
            let pairs = stride(from: 0, to: rows.count, by: 2).map { Array(rows[$0..<min($0 + 2, rows.count)]) }
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 8 * ui) {
                    ForEach(pair) { row in
                        looseRow(row)
                    }
                    if pair.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Self.rowHeight * ui)
                // The editor of either of the two opens under their line, across both.
                if pair.contains(where: { $0.id == model.editing?.id }) {
                    editorCard
                }
            }
        }
    }

    /// A finished reminder: ticked, struck through and fainter. A click on its tick makes
    /// it open again; there is nothing else to do with it here.
    private func doneRow(_ row: DayTimeline.Row) -> some View {
        HStack(spacing: 5 * ui) {
            Button {
                if let reminder = model.doneReminders[row.id] {
                    model.onReopen?(reminder)
                }
            } label: {
                AraIcon.completed.image
                    .font(.system(size: 11 * ui))
                    .foregroundStyle(AraPalette.value.opacity(0.8))
                    .frame(width: 16 * ui, height: 16 * ui)
                    .contentShape(Rectangle())
            }
            .buttonStyle(AraPressStyle(depth: 0.8))
            .help(L10n.string("calendar.reminder.reopen"))
            .accessibilityLabel(L10n.string("calendar.reminder.reopen"))
            Text(row.title)
                .font(.system(size: 11 * ui))
                .strikethrough()
                .foregroundStyle(AraTheme.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0 * ui)
        }
        .padding(.trailing, 4 * ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help(row.title)
    }

    @ViewBuilder
    private func looseRow(_ row: DayTimeline.Row) -> some View {
        if row.isDone {
            doneRow(row)
        } else {
            openRow(row)
        }
    }

    private func openRow(_ row: DayTimeline.Row) -> some View {
        AraHoverLift(scale: 1) { isHovered in
            HStack(spacing: 5 * ui) {
                if let reminder = model.timelineReminders[row.id] {
                    CompleteButton { model.onComplete?(reminder) }
                        .scaleEffect(0.8)
                        .frame(width: 16 * ui, height: 16 * ui)
                }
                Text(row.title)
                    .font(.system(size: 11 * ui))
                    .lineLimit(1)
                    // VoiceOver, and anything else that presses rather than clicks, does the
                    // same as a click. On the name alone: set on the whole row it would also
                    // take the place of what the tick beside it does.
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        if let reminder = model.timelineReminders[row.id] {
                            model.onEditReminder?(reminder)
                        }
                    }
                Spacer(minLength: 0 * ui)
            }
            .padding(.trailing, 4 * ui)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isHovered ? AraPalette.hoverWash : .clear, in: RoundedRectangle(cornerRadius: 6 * ui, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if let reminder = model.timelineReminders[row.id] {
                    model.onEditReminder?(reminder)
                }
            }
            .araTooltip(row.title, isHovered: isHovered)
        }
    }

    // MARK: - Changing a reminder in place

    /// The reminder's editor, opened under its row: its name and notes to type, and
    /// everything else as chips to click. Nothing is written until Done.
    @ViewBuilder
    private var editorCard: some View {
        if let detail = model.editing {
            VStack(alignment: .leading, spacing: ReminderEditorLayout.spacing * ui) {
                HStack(spacing: 6 * ui) {
                    TextField(
                        L10n.string("calendar.reminder.placeholder"),
                        text: Binding(get: { model.editing?.title ?? "" }, set: { model.editing?.title = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12 * ui, weight: .semibold))
                        .onSubmit { model.onSaveEditing?() }
                    // The list it is kept in stands beside its name, as the reminders app has it.
                    fieldChip(
                        .list, icon: .list,
                        text: model.reminderLists.first { $0.id == detail.listID }?.name ?? L10n.string("calendar.editor.list"),
                        help: L10n.string("calendar.editor.list"))
                        .frame(maxWidth: 130 * ui, alignment: .trailing)
                        .scaleEffect(0.84, anchor: .trailing)
                    AraIconButton(.openLink, look: .bare, size: .small, help: L10n.string("calendar.reminder.open")) {
                        if let reminder = model.timelineReminders[detail.id] {
                            model.onOpenReminder?(reminder)
                        }
                    }
                }
                .frame(height: ReminderEditorLayout.titleHeight * ui)
                TextField(
                    L10n.string("calendar.editor.notes"),
                    text: Binding(get: { model.editing?.notes ?? "" }, set: { model.editing?.notes = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11 * ui))
                    .foregroundStyle(AraPalette.ink.opacity(0.85))
                    .frame(height: ReminderEditorLayout.notesHeight * ui)
                HStack(spacing: 3 * ui) {
                    editorChip(
                        .calendar, editingDueText(long: false), isOn: model.picker == .editing, isSet: detail.due != nil,
                        help: L10n.string("calendar.editor.due.help")
                    ) {
                        model.editingField = nil
                        model.picker = .editing
                    }
                    // When the row is tight the others give way first: the day and time stay whole.
                    .fixedSize()
                    .layoutPriority(1)
                    fieldChip(
                        .repeats, icon: .reset, text: L10n.string("calendar.repeat.\(detail.repeats.rawValue)"),
                        isSet: detail.repeats != .never, help: L10n.string("calendar.repeat.help"))
                        // Only what has a day comes round again, and only what has an hour alerts early.
                        .disabled(detail.due == nil)
                        .opacity(detail.due == nil ? 0.45 : 1)
                    fieldChip(
                        .alert, icon: .remind,
                        text: detail.alertMinutes.map {
                            String(format: L10n.string("calendar.early.chip"), Self.alertText($0))
                        } ?? Self.alertText(nil),
                        isSet: detail.alertMinutes != nil, help: L10n.string("calendar.early.help"))
                        .disabled(!detail.dueHasTime)
                        .opacity(detail.dueHasTime ? 1 : 0.45)
                    // Left as it comes, a field shows its own name: five chips share the row.
                    fieldChip(
                        .priority, icon: .warning,
                        text: L10n.string(
                            detail.priority == .none ? "calendar.priority.unset" : "calendar.priority.\(detail.priority.rawValue)"),
                        isSet: detail.priority != .none, help: L10n.string("calendar.priority.help"))
                    fieldChip(
                        .estimate, icon: .timer,
                        text: detail.estimateMinutes.map(Self.durationText) ?? L10n.string("calendar.estimate.unset"),
                        isSet: detail.estimateMinutes != nil, help: L10n.string("calendar.estimate.help"))
                        // The work ends at the due time, so there must be one.
                        .disabled(!detail.dueHasTime)
                        .opacity(detail.dueHasTime ? 1 : 0.45)
                    Spacer(minLength: 0 * ui)
                }
                .frame(height: ReminderEditorLayout.chipsHeight * ui)
                if let field = model.editingField {
                    // Lists may be many; the others are few enough to stand in one row.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4 * ui) {
                            choices(of: field, in: detail)
                        }
                    }
                    .frame(height: ReminderEditorLayout.chipsHeight * ui)
                }
                HStack(spacing: 6 * ui) {
                    AraPillButton(L10n.string("picker.done"), icon: .confirm, isProminent: true) { model.onSaveEditing?() }
                    AraPillButton(L10n.string("settings.cancel"), icon: .close) { model.onCancelEditing?() }
                    Spacer(minLength: 0 * ui)
                    // Two presses: the first asks, the second removes.
                    AraPillButton(
                        L10n.string(model.confirmsDelete ? "calendar.editor.delete.confirm" : "calendar.editor.delete"),
                        icon: .delete, isDestructive: true
                    ) {
                        model.onDeleteEditing?()
                    }
                }
                .scaleEffect(0.9, anchor: .leading)
                .frame(height: ReminderEditorLayout.buttonsHeight * ui)
            }
            .padding(.horizontal, 8 * ui)
            .padding(.vertical, ReminderEditorLayout.padding * ui / 2)
            .araCard(radius: AraTheme.rowRadius, level: .raised)
            .padding(.vertical, ReminderEditorLayout.margin * ui / 2)
        }
    }

    /// A chip of the editor that opens the choices of one field under the chips.
    private func fieldChip(
        _ field: ReminderField, icon: AraIcon, text: String, isSet: Bool = true, help: String
    ) -> some View {
        editorChip(icon, text, isOn: model.editingField == field, isSet: isSet, help: help) {
            model.editingField = model.editingField == field ? nil : field
        }
    }

    /// - Parameter isSet: false for a field left as it comes ("No repeat"), which reads fainter.
    private func editorChip(
        _ icon: AraIcon, _ text: String, isOn: Bool, isSet: Bool, help: String, action: @escaping () -> Void
    ) -> some View {
        AraChip(isSelected: isOn, action: action) {
            HStack(spacing: 4 * ui) {
                icon.image.font(.system(size: 9 * ui, weight: .semibold))
                Text(text)
                    .font(.system(size: 10.5 * ui, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    // The longest values of every chip at once are a little wider than the card.
                    .minimumScaleFactor(0.8)
            }
            .opacity(isSet || isOn ? 1 : 0.6)
            // Five chips share the row: each a little narrower than the usual chip.
            .padding(.horizontal, -3 * ui)
        }
        .help(help)
        .accessibilityLabel("\(help): \(text)")
    }

    /// The choices of one field, the current one filled; a click takes it.
    @ViewBuilder
    private func choices(of field: ReminderField, in detail: ReminderDetail) -> some View {
        switch field {
        case .repeats:
            ForEach(ReminderRepeat.allCases, id: \.self) { choice in
                choiceChip(L10n.string("calendar.repeat.\(choice.rawValue)"), isOn: detail.repeats == choice) {
                    model.editing?.repeats = choice
                }
            }
        case .alert:
            ForEach(Array(ReminderDetail.alertChoices.enumerated()), id: \.offset) { _, minutes in
                choiceChip(Self.alertText(minutes), isOn: detail.alertMinutes == minutes) {
                    model.editing?.alertMinutes = minutes
                }
            }
        case .priority:
            ForEach(ReminderPriority.allCases, id: \.self) { choice in
                choiceChip(L10n.string("calendar.priority.\(choice.rawValue)"), isOn: detail.priority == choice) {
                    model.editing?.priority = choice
                }
            }
        case .estimate:
            ForEach(Array(ReminderDetail.estimateChoices.enumerated()), id: \.offset) { _, minutes in
                choiceChip(
                    minutes.map(Self.durationText) ?? L10n.string("calendar.estimate.none"),
                    isOn: detail.estimateMinutes == minutes
                ) {
                    model.editing?.estimateMinutes = minutes
                }
            }
        case .list:
            ForEach(model.reminderLists) { list in
                choiceChip(list.name, isOn: detail.listID == list.id) {
                    model.editing?.listID = list.id
                }
            }
        }
    }

    /// The row of choices stays after one is taken, so another can be tried and seen on the
    /// chart; it goes with Done, or when its chip is clicked again or another one opened.
    private func choiceChip(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        AraChip(isSelected: isOn, action: action) {
            Text(text)
                .font(.system(size: 10.5 * ui, weight: .medium))
                .lineLimit(1)
        }
    }

    /// When the reminder being changed is due, in words.
    private func editingDueText(long: Bool) -> String {
        guard let detail = model.editing, let due = detail.due else { return L10n.string("calendar.reminder.noDue") }
        if detail.dueHasTime {
            return (long ? Self.dueTitle : Self.dueShort).string(from: due)
        }
        return (long ? Self.fullDay : Self.date).string(from: due)
    }

    /// How long before it is due a reminder alerts: "On time", "5 min", "1 day".
    private static func alertText(_ minutes: Int?) -> String {
        minutes.map(durationText) ?? L10n.string("calendar.early.none")
    }

    /// A length of time in words: "30 min", "2 h", "1 day".
    private static func durationText(_ minutes: Int) -> String {
        if minutes >= 1_440 { return String(format: L10n.string("calendar.early.days"), minutes / 1_440) }
        if minutes >= 60 { return String(format: L10n.string("calendar.early.hours"), minutes / 60) }
        return String(format: L10n.string("calendar.early.minutes"), minutes)
    }

    /// One row of the chart: what it is on the left, and when it is as a bar or a mark
    /// across the hours.
    private func chartRow(_ row: DayTimeline.Row, in timeline: DayTimeline) -> some View {
        AraHoverLift(scale: 1) { isHovered in
            HStack(spacing: 0 * ui) {
                HStack(spacing: 5 * ui) {
                    if row.kind == .reminder, let reminder = model.timelineReminders[row.id] {
                        CompleteButton { model.onComplete?(reminder) }
                            .scaleEffect(0.8)
                            .frame(width: 16 * ui, height: 16 * ui)
                    } else {
                        RoundedRectangle(cornerRadius: 1.5 * ui)
                            .fill(Self.color(row.tint))
                            .frame(width: 3 * ui, height: 13 * ui)
                            .frame(width: 16 * ui)
                    }
                    Text(row.title)
                        .font(.system(size: 11 * ui, weight: row.kind == .event ? .semibold : .regular))
                        .lineLimit(1)
                        // Pressing the name does what a click on the row does; the tick keeps its own.
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            if row.kind == .event, let event = model.timelineEvents[row.id] {
                                model.onOpenEvent?(event)
                            } else if let reminder = model.timelineReminders[row.id] {
                                model.onEditReminder?(reminder)
                            }
                        }
                    Spacer(minLength: 0 * ui)
                }
                .frame(width: (Self.labelWidth - 6) * ui, alignment: .leading)
                .padding(.trailing, 6 * ui)
                GeometryReader { area in
                    chartMark(row, in: timeline, width: area.size.width)
                }
            }
            .frame(height: Self.rowHeight * ui)
            .background(isHovered ? AraPalette.hoverWash : .clear, in: RoundedRectangle(cornerRadius: 6 * ui, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture {
                if row.kind == .event, let event = model.timelineEvents[row.id] {
                    model.onOpenEvent?(event)
                } else if let reminder = model.timelineReminders[row.id] {
                    model.onEditReminder?(reminder)
                }
            }
            .araTooltip(Self.detail(of: row), isHovered: isHovered)
        }
    }

    @ViewBuilder
    private func chartMark(_ row: DayTimeline.Row, in timeline: DayTimeline, width: CGFloat) -> some View {
        let tint = row.kind == .event ? Self.color(row.tint) : AraPalette.label(in: hue)
        if row.isAllDay {
            // The whole day: a pale bar from edge to edge.
            Capsule()
                .fill(tint.opacity(0.35))
                .frame(width: width, height: 8 * ui)
                .offset(y: (Self.rowHeight - 8) * ui / 2)
        } else if let start = row.start, let end = row.end {
            let x = width * timeline.position(ofHour: start)
            Capsule()
                .fill(tint)
                .frame(width: max(width * timeline.position(ofHour: end) - x, 6), height: 10 * ui)
                .offset(x: x, y: (Self.rowHeight - 10) * ui / 2)
        } else if let start = row.start {
            // A reminder is a moment: a mark where it is due. With an estimate, the work
            // runs up to that mark as a paler bar, the due time being its deadline.
            let x = width * timeline.position(ofHour: start)
            let color = row.isOverdue ? AraPalette.danger : tint
            ZStack(alignment: .topLeading) {
                if let workStart = row.workStart {
                    let from = min(width * timeline.position(ofHour: workStart), x - 6 * ui)
                    Capsule()
                        .fill(color.opacity(0.4))
                        .frame(width: x - from, height: 10 * ui)
                        .offset(x: from, y: (Self.rowHeight - 10) * ui / 2)
                }
                Circle()
                    .fill(color)
                    .frame(width: 9 * ui, height: 9 * ui)
                    .offset(x: x - 4.5 * ui, y: (Self.rowHeight - 9) * ui / 2)
            }
        } else {
            Text(L10n.string(row.isOverdue ? "calendar.chart.overdue" : "calendar.chart.anytime"))
                .font(.system(size: 9.5 * ui, weight: .medium))
                .foregroundStyle(row.isOverdue ? AraPalette.danger : AraTheme.secondaryText)
                .frame(height: Self.rowHeight * ui)
        }
    }

    /// What a row says under the pointer: its name and its hours.
    private static func detail(of row: DayTimeline.Row) -> String {
        func clockOf(_ hour: Double) -> String { clock(Int((hour * 60).rounded())) }
        if row.isAllDay { return "\(row.title) · \(L10n.string("calendar.allDay"))" }
        if let start = row.start, let end = row.end { return "\(row.title) · \(clockOf(start)) – \(clockOf(end))" }
        if let start = row.start, let workStart = row.workStart {
            return "\(row.title) · \(clockOf(workStart)) – \(clockOf(start))"
        }
        if let start = row.start { return "\(row.title) · \(clockOf(start))" }
        return row.title
    }

    // MARK: - Events

    static func timeText(_ event: AgendaEvent) -> String {
        if event.isAllDay { return L10n.string("calendar.allDay") }
        return "\(time.string(from: event.start)) – \(time.string(from: event.end))"
    }

    /// An event being typed for the day shown: its title, when it starts, then Return or the
    /// tick to put it in the calendar.
    private var eventDraftRow: some View {
        HStack(spacing: 6 * ui) {
            RoundedRectangle(cornerRadius: 1.5 * ui)
                .fill(AraPalette.label(in: hue))
                .frame(width: 3 * ui, height: 20 * ui)
            TextField(
                L10n.string("calendar.event.placeholder"),
                text: Binding(get: { model.eventDraft?.title ?? "" }, set: { model.eventDraft?.title = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 12 * ui, weight: .medium))
                .onSubmit { commitEvent() }
            // The day and the time, chosen by sight on a month and a clock face.
            whenChip(eventWhenText, help: L10n.string("calendar.event.time")) { model.picker = .event }
            AraIconButton(.confirm, look: .accent, size: .small, help: L10n.string("calendar.event.add")) { commitEvent() }
            AraIconButton(.close, look: .bare, size: .small) { model.eventDraft = nil }
        }
        .padding(.horizontal, 6 * ui)
        .frame(height: 34 * ui)
        .araCard(radius: AraTheme.rowRadius, level: .raised)
    }

    /// The button on a draft's row that says when, and opens the picker.
    private func whenChip(_ text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3 * ui) {
                AraIcon.calendar.image.font(.system(size: 8.5 * ui, weight: .bold))
                Text(text)
                    .font(.system(size: 10 * ui, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 7 * ui)
            .frame(height: 20 * ui)
            .background(AraPalette.hoverWash, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(AraPressStyle())
        .fixedSize()
        .help(help)
    }

    /// "15/10 14:30": a reminder's due time, short enough for its row.
    private static let dueShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMHHmm")
        return formatter
    }()

    private func commitEvent() {
        if let draft = model.eventDraft {
            model.onAddEvent?(draft)
        }
    }

    // MARK: - Reminders

    /// A reminder being typed: Return keeps it, the cross gives up.
    private var draftRow: some View {
        HStack(spacing: 8 * ui) {
            AraIcon.complete.image
                .font(.system(size: 14 * ui))
                .foregroundStyle(AraPalette.ink.opacity(0.35))
                .frame(width: 22 * ui, height: 22 * ui)
            TextField(
                L10n.string("calendar.reminder.placeholder"),
                text: Binding(get: { model.reminderDraft ?? "" }, set: { model.reminderDraft = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 12 * ui, weight: .medium))
                .onSubmit { model.onAddReminder?(model.reminderDraft ?? "") }
            whenChip(
                model.reminderDue.map(Self.dueShort.string) ?? L10n.string("calendar.reminder.due"),
                help: L10n.string("calendar.reminder.due")
            ) {
                model.picker = .reminder
            }
            AraIconButton(.confirm, look: .accent, size: .small, help: L10n.string("calendar.reminder.add")) {
                model.onAddReminder?(model.reminderDraft ?? "")
            }
            AraIconButton(.close, look: .bare, size: .small) { model.reminderDraft = nil }
        }
        .padding(.horizontal, 6 * ui)
        .frame(height: 30 * ui)
        .araCard(radius: AraTheme.rowRadius, level: .raised)
    }

    // MARK: - Pieces

    private static func color(_ tint: UInt32?) -> Color {
        guard let tint else { return AraPalette.ink.opacity(0.4) }
        return Color(
            .sRGB, red: Double(tint >> 16 & 0xFF) / 255, green: Double(tint >> 8 & 0xFF) / 255,
            blue: Double(tint & 0xFF) / 255)
    }

    /// "09:30" for a number of minutes after midnight, in the user's way of writing the time.
    private static func clock(_ minutes: Int) -> String {
        let start = Calendar.current.startOfDay(for: Date())
        return time.string(from: Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start)
    }

    private static let fullDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()

    /// "Wed 14 Oct": the heading of a day that is not today.
    private static let dayTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dM")
        return formatter
    }()
}

/// The circle that ticks a reminder off: it previews the tick under the pointer.
struct CompleteButton: View {
    @Environment(\.araScale) private var ui
    let action: () -> Void
    @StateObject private var hover = AraHover()

    var body: some View {
        Button(action: action) {
            (hover.isHovered ? AraIcon.completed : AraIcon.complete).image
                .font(.system(size: 14 * ui))
                .foregroundStyle(hover.isHovered ? AnyShapeStyle(AraPalette.value) : AnyShapeStyle(AraPalette.ink.opacity(0.6)))
                .frame(width: 22 * ui, height: 22 * ui)
                .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.8))
        .onHover { hover.isHovered = $0 }
        .help(L10n.string("calendar.reminder.complete"))
        .accessibilityLabel(L10n.string("calendar.reminder.complete"))
    }
}
