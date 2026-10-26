import Foundation

/// When a widget turns from its own colour to the alert orange: something
/// wants the user soon.
public enum WidgetAlert {
    /// A battery at a fifth or less that is not charging. A device that reports no charge never alerts.
    public static func battery(percent: Int?, isCharging: Bool) -> Bool {
        guard let percent, !isCharging else { return false }
        return percent <= 20
    }

    /// A rate limit used to 90% or more.
    public static func usage(percent: Double?) -> Bool {
        guard let percent else { return false }
        return percent >= 90
    }

    /// A countdown in its last minute, or one that has ended.
    public static func timer(remaining: TimeInterval, isFinished: Bool) -> Bool {
        isFinished || remaining < 60
    }

    /// An agent waiting for the user.
    public static func agents(waiting: Int) -> Bool {
        waiting > 0
    }
}
