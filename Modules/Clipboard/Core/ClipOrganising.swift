import Foundation

/// A time to be reminded of a clip at.
public enum ClipReminderPreset: String, CaseIterable, Sendable {
    case inThirtyMinutes
    case inOneHour
    case inThreeHours
    /// Eight in the evening, today or, when that has passed, tomorrow.
    case thisEvening
    /// Nine in the morning of the next day.
    case tomorrowMorning

    public func due(from now: Date, calendar: Calendar) -> Date {
        switch self {
        case .inThirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .inOneHour:
            return now.addingTimeInterval(3600)
        case .inThreeHours:
            return now.addingTimeInterval(3 * 3600)
        case .thisEvening:
            let today = calendar.startOfDay(for: now)
            let evening = calendar.date(byAdding: .hour, value: 20, to: today) ?? now
            return evening > now ? evening : (calendar.date(byAdding: .day, value: 1, to: evening) ?? evening)
        case .tomorrowMorning:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(byAdding: .hour, value: 9, to: tomorrow) ?? tomorrow
        }
    }
}

/// The words a reminder about a clip is made of.
public enum ClipReminderText {
    static let maxTitleLength = 80
    static let maxNotesLength = 2000

    /// The clip's own title, or its first line; `fallback` for clips without text.
    public static func title(for item: ClipItem, fallback: String) -> String {
        if let title = item.title, !title.isEmpty { return title }
        let firstLine = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        guard !firstLine.isEmpty, item.kind != .image else { return fallback }
        return firstLine.count > maxTitleLength ? String(firstLine.prefix(maxTitleLength)) + "…" : firstLine
    }

    /// The clip's text, for the body of the reminder; nil for clips without text.
    public static func notes(for item: ClipItem) -> String? {
        guard item.kind != .image, !item.isEncrypted else { return nil }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(maxNotesLength))
    }
}

/// A search the user saved, to get the same list again with one click.
public struct SavedFilter: Equatable, Identifiable, Sendable {
    /// How many are kept; a new one beyond that replaces the oldest.
    public static let limit = 8

    /// The search as typed, filters such as `@image` included.
    public var query: String

    public var id: String { query }

    public init(query: String) {
        self.query = query
    }

    /// The list with this search added at the end. An empty search, or one already there, changes nothing.
    public static func adding(_ query: String, to filters: [SavedFilter]) -> [SavedFilter] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !filters.contains(where: { $0.query == trimmed }) else { return filters }
        return Array((filters + [SavedFilter(query: trimmed)]).suffix(limit))
    }

    public static func removing(_ query: String, from filters: [SavedFilter]) -> [SavedFilter] {
        filters.filter { $0.query != query }
    }
}

/// The order the history is listed in.
public enum ClipSortOrder: String, CaseIterable, Sendable {
    /// Last copied or pasted first: the order the history is kept in.
    case recentlyUsed
    /// Last captured first.
    case newest
    case oldest
    /// By title, or by text for clips without one, ignoring case and accents.
    case name

    /// - Parameter items: the history as stored, most recently used first.
    public func sorted(_ items: [ClipItem]) -> [ClipItem] {
        switch self {
        case .recentlyUsed:
            return items
        case .newest:
            return items.sorted { ($0.createdAt, $0.id) > ($1.createdAt, $1.id) }
        case .oldest:
            return items.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        case .name:
            func key(_ item: ClipItem) -> String {
                SearchFolding.fold((item.title?.isEmpty == false ? item.title : nil) ?? item.text)
            }
            return items.sorted { (key($0), $0.id) < (key($1), $1.id) }
        }
    }
}

/// Names for boards the user has not named.
public enum BoardNames {
    /// "Board 3": the base word with the first number no board carries yet, whatever its capitals.
    public static func suggested(base: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        var number = 1
        while taken.contains("\(base) \(number)".lowercased()) {
            number += 1
        }
        return "\(base) \(number)"
    }
}

/// When a fingerprint may stand in for the passcode of the locked boards.
public enum VaultTouchID {
    public static func shouldOffer(
        isEnabled: Bool, hasSavedPasscode: Bool, canUseBiometrics: Bool, isCreating: Bool
    ) -> Bool {
        isEnabled && hasSavedPasscode && canUseBiometrics && !isCreating
    }
}
