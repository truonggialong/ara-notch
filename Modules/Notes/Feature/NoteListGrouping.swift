import Foundation
import NotesCore

/// The date groups of the Notes window's list, as Notes shows them: Today, Yesterday, Previous 7 Days,
/// Previous 30 Days, then one group per month, newest first.
enum NoteListGrouping {
    /// Groups `notes` by how long ago they were changed, counted in calendar days of `calendar`. Each group is newest
    /// first. A month group's key is `notes.group.month`; its name comes from `monthTitle(of:)` of any of its notes.
    static func groups(_ notes: [NoteSummary], now: Date, calendar: Calendar) -> [(titleKey: String, notes: [NoteSummary])] {
        let today = calendar.startOfDay(for: now)
        var result: [(titleKey: String, notes: [NoteSummary])] = []
        var monthOfGroup: [DateComponents?] = []
        for note in notes.sorted(by: { $0.modified > $1.modified }) {
            let day = calendar.startOfDay(for: note.modified)
            let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let key: String
            var month: DateComponents?
            switch daysAgo {
            case ..<1: key = "notes.group.today"   // a date ahead of the clock counts as today
            case 1: key = "notes.group.yesterday"
            case 2...7: key = "notes.group.previous7"
            case 8...30: key = "notes.group.previous30"
            default:
                key = "notes.group.month"
                month = calendar.dateComponents([.year, .month], from: note.modified)
            }
            // Sorted newest first, so a note joins the last group or starts the next one.
            if let last = result.indices.last, result[last].titleKey == key, monthOfGroup[last] == month {
                result[last].notes.append(note)
            } else {
                result.append((key, [note]))
                monthOfGroup.append(month)
            }
        }
        return result
    }

    static var appLocale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    /// The name of a month group: "August", or "August 2025" for another year than `now`'s.
    /// `locale`: the app's language by default (as the Calendar widget does), not the system's region.
    static func monthTitle(of date: Date, now: Date, calendar: Calendar, locale: Locale = appLocale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "LLLL" : "LLLL yyyy")
        let title = formatter.string(from: date)
        return title.prefix(1).uppercased(with: locale) + title.dropFirst()
    }
}
