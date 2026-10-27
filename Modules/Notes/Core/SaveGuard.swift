import Foundation

public enum SaveDecision: Equatable, Sendable { case write, conflict }

/// Detects a note that changed elsewhere since it was opened.
public enum SaveGuard {
    /// AppleScript dates are rounded to the second, so up to one second of difference is the same moment.
    /// Any larger difference, in either direction, means the note is not the one that was opened.
    public static func decide(openedAt: Date, currentModification: Date) -> SaveDecision {
        abs(currentModification.timeIntervalSince(openedAt)) > 1 ? .conflict : .write
    }
}
