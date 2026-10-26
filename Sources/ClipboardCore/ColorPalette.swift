import Foundation

/// The colours for the overview's palette tile: the newest colour clips, each colour once,
/// never one kept in a locked board.
public enum ColorPalette {
    /// In the order given (newest first), at most `limit`.
    public static func recent(_ items: [ClipItem], limit: Int) -> [ClipItem] {
        var seen = Set<String>()
        var colors: [ClipItem] = []
        for item in items where item.kind == .color && !item.isEncrypted {
            guard colors.count < limit else { break }
            let key = ClipColor.parse(item.text, allowingBareHex: true)?.formatted(as: .hex) ?? item.text
            if seen.insert(key.uppercased()).inserted {
                colors.append(item)
            }
        }
        return colors
    }
}

/// How many clips the clipboard widget counts as today's: copied or pasted today, never one
/// kept in a locked board.
public enum ClipToday {
    /// `items` is the history as it is kept, last used first, so the count stops at the
    /// first clip from an earlier day instead of reading the whole history.
    public static func count(_ items: [ClipItem], now: Date, calendar: Calendar) -> Int {
        var count = 0
        for item in items {
            guard calendar.isDate(item.lastUsedAt, inSameDayAs: now) else { break }
            if !item.isEncrypted { count += 1 }
        }
        return count
    }
}
