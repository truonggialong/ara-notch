import Foundation

public enum SaveDecision: Equatable, Sendable { case write, conflict }

/// Detects a note that changed elsewhere since it was opened.
public enum SaveGuard {
    /// Both dates come from AppleScript, rounded to the second the same way, so only equal dates are the same moment.
    /// Any other date, even one second apart and in either direction, means the note is not the one that was opened
    /// (an edit synced in right after AraNotch's write shows as one second later). Notes does not move the date by
    /// itself after `set body` (checked on macOS 27).
    public static func decide(openedAt: Date, currentModification: Date) -> SaveDecision {
        currentModification == openedAt ? .write : .conflict
    }
}
