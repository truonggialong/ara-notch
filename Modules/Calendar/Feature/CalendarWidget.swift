import CalendarCore
import NotchShell
import SwiftUI

/// Today as a widget of the overview. Small: when the next thing starts, large, and what it
/// is. Wide: that, how many things are left, and the day as a bar with "now" on it. Large: the
/// day's events and reminders, a line each, Join for a call, a circle that finishes a reminder.
struct CalendarWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    @ObservedObject var model: CalendarViewModel
    @ObservedObject var settings: CalendarSettings
    let onOpen: () -> Void

    var body: some View {
        let summary = DaySummary.make(events: model.agenda.today, reminders: model.reminders, at: model.now, calendar: .current)
        AraWidget(name: L10n.string("page.calendar.title"), hue: .mustard, onOpen: onOpen) {
            if model.eventAccess != .granted, model.reminderAccess != .granted {
                access
            } else {
                switch size {
                case .small: small(summary)
                case .wide: wide(summary)
                case .large: large(summary)
                }
            }
        }
        .onAppear { model.onAppear?() }
    }

    /// Without access to the calendar or the reminders: the same request as on the calendar page.
    private var access: some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            AraWidgetHeader(label: L10n.string("page.calendar.title"))
            Spacer(minLength: 0)
            let refused = model.eventAccess == .denied
            Button {
                if refused { model.onOpenPrivacySettings?(false) } else { model.onRequestEvents?() }
            } label: {
                Text(L10n.string(refused ? "calendar.denied.events" : "calendar.access.events"))
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.widgetCard)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10 * ui)
                    .frame(height: 24 * ui)
                    .background(Capsule().fill(AraPalette.vivid(.mustard)))
            }
            .buttonStyle(AraPressStyle())
        }
    }

    private func small(_ summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 1 * ui) {
            if let next = summary.next {
                AraWidgetHeader(label: L10n.string("widget.calendar.next"), chip: untilChip(next))
                Spacer(minLength: 0)
                AraBigValue(Self.time.string(from: next), size: 24)
                Text(summary.nextTitle ?? "")
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .lineLimit(1)
            } else {
                nothingLeft(summary)
            }
        }
    }

    private func wide(_ summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = summary.next {
                AraWidgetHeader(label: nextLabel(next), chip: countChip(summary))
                HStack(alignment: .firstTextBaseline, spacing: 8 * ui) {
                    AraBigValue(Self.time.string(from: next), size: 26)
                        .fixedSize()
                    Text(summary.nextTitle ?? "")
                        .font(.system(size: 12 * ui, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 2 * ui)
                dayBar
            } else {
                nothingLeft(summary)
                dayBar
            }
        }
    }

    private func large(_ summary: DaySummary) -> some View {
        // Six lines: today's events and reminders first, then the overdue under a line of their own.
        let list = DayList.make(events: model.agenda.today, reminders: model.reminders, at: model.now, calendar: .current)
        let events = Array(list.events.prefix(6))
        let reminders = Array(list.dueToday.prefix(6 - events.count))
        let overdueRoom = 6 - events.count - reminders.count - 1
        let overdue = overdueRoom > 0 ? Array(list.overdue.prefix(overdueRoom)) : []
        return VStack(alignment: .leading, spacing: 2 * ui) {
            AraWidgetHeader(label: String(format: L10n.string("widget.calendar.today"), Self.day.string(from: model.now)), chip: countChip(summary))
            if events.isEmpty, reminders.isEmpty {
                Text(L10n.string("widget.calendar.none"))
                    .font(.system(size: 12 * ui, weight: .semibold))
            }
            ForEach(events) { event in
                HStack(spacing: 7 * ui) {
                    RoundedRectangle(cornerRadius: 1.5 * ui)
                        .fill(Self.color(event.tint))
                        .frame(width: 3 * ui, height: 14 * ui)
                    Text(event.isAllDay ? L10n.string("calendar.allDay") : Self.time.string(from: event.start))
                        .font(.system(size: 11 * ui, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AraPalette.vivid(.mustard))
                        .fixedSize()
                    Text(event.title)
                        .font(.system(size: 11 * ui, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 2 * ui)
                    if let link = event.joinURL {
                        Button {
                            model.onJoin?(link)
                        } label: {
                            Text(L10n.string("calendar.join"))
                                .font(.system(size: 10.5 * ui, weight: .semibold))
                                .foregroundStyle(AraPalette.widgetCard)
                                .padding(.horizontal, 7 * ui)
                                .frame(height: 15 * ui)
                                .background(Capsule().fill(AraPalette.vivid(.mustard)))
                        }
                        .buttonStyle(AraPressStyle())
                    } else if !event.isAllDay {
                        Text(Self.length(minutes: Int(event.end.timeIntervalSince(event.start) / 60)))
                            .font(.system(size: 10.5 * ui))
                            .foregroundStyle(AraPalette.widgetSecondary)
                            .fixedSize()
                    }
                }
                .frame(height: 15 * ui)
            }
            ForEach(reminders) { reminder in
                HStack(spacing: 7 * ui) {
                    CompleteButton { model.onComplete?(reminder) }
                        .frame(width: 13 * ui, height: 13 * ui)
                    Text(reminder.title)
                        .font(.system(size: 11 * ui))
                        .lineLimit(1)
                }
                .frame(height: 15 * ui)
            }
            if !list.overdue.isEmpty, overdueRoom >= 0 {
                Text(String(format: L10n.string("widget.calendar.overdueTitle"), list.overdue.count))
                    .font(.system(size: 10.5 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.alert)
                    .frame(height: 15 * ui)
                ForEach(overdue) { reminder in
                    HStack(spacing: 7 * ui) {
                        CompleteButton { model.onComplete?(reminder) }
                            .frame(width: 13 * ui, height: 13 * ui)
                        Text(reminder.title)
                            .font(.system(size: 11 * ui))
                            .lineLimit(1)
                    }
                    .frame(height: 15 * ui)
                }
            }
            Spacer(minLength: 0)
            dayBar
        }
    }

    /// No timed thing left: the day's all-day event or open reminder, or that nothing is left.
    @ViewBuilder
    private func nothingLeft(_ summary: DaySummary) -> some View {
        if summary.count == 0 {
            AraWidgetHeader(label: L10n.string("page.calendar.title"), chip: countChip(summary))
            Spacer(minLength: 0)
            Text(L10n.string("widget.calendar.none"))
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        } else {
            AraWidgetHeader(label: L10n.string("calendar.today"), chip: countChip(summary))
            Spacer(minLength: 0)
            Text(restOfDay ?? "")
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    /// Today's all-day event or first reminder without a time.
    private var restOfDay: String? {
        let list = DayList.make(events: model.agenda.today, reminders: model.reminders, at: model.now, calendar: .current)
        return list.events.first?.title ?? list.dueToday.first?.title
    }

    /// The day from midnight to midnight: its timed events as spans, "now" as an orange mark.
    private var dayBar: some View {
        AraTrackBar(
            fraction: 0, hue: .mustard,
            spans: DayRing.arcs(for: model.agenda.today, on: model.now, calendar: .current),
            marker: DayRing.fraction(of: model.now, on: model.now, calendar: .current))
    }

    private func untilChip(_ next: Date) -> AraStatusChip? {
        untilText(next).map { AraStatusChip(text: $0, hue: .mustard) }
    }

    private func untilText(_ next: Date) -> String? {
        switch UntilNext.make(next: next, now: model.now) {
        case .now: L10n.string("widget.calendar.now")
        case .minutes(let minutes): String(format: L10n.string("widget.calendar.inMinutes"), minutes)
        case .hours(let hours): String(format: L10n.string("widget.calendar.inHours"), hours)
        case nil: nil
        }
    }

    /// "Up next · in 40′".
    private func nextLabel(_ next: Date) -> String {
        [L10n.string("widget.calendar.next"), untilText(next)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The overdue, in orange, when there are any: they want the user more than what is left
    /// of today; else how many things today still holds.
    private func countChip(_ summary: DaySummary) -> AraStatusChip? {
        if summary.overdue > 0 {
            return AraStatusChip(text: String(format: L10n.string("widget.calendar.overdue"), summary.overdue), hue: .mustard, isAlert: true)
        }
        return summary.count > 0 ? AraStatusChip(text: String(format: L10n.string("widget.calendar.left"), summary.count), hue: .mustard) : nil
    }

    /// The colour of the event's calendar.
    private static func color(_ tint: UInt32?) -> Color {
        guard let tint else { return AraPalette.vivid(.mustard) }
        return Color(
            .sRGB, red: Double(tint >> 16 & 0xFF) / 255, green: Double(tint >> 8 & 0xFF) / 255,
            blue: Double(tint & 0xFF) / 255)
    }

    /// An event's length: "45′", "2 h", "1 h 30′".
    private static func length(minutes: Int) -> String {
        if minutes < 60 { return String(format: L10n.string("widget.duration.minutes"), minutes) }
        if minutes % 60 == 0 { return String(format: L10n.string("widget.duration.hours"), minutes / 60) }
        return String(format: L10n.string("widget.duration.hoursMinutes"), minutes / 60, minutes % 60)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// "Monday, 18 October", in the app's language.
    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()
}
