import Foundation

public enum TimerFormat {
    /// "24:59" or "1:05:00". Rounds up to the next whole second, so a countdown shows "1:00"
    /// until a full second has passed and reaches "0:00" only when it is over.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isNaN ? 0 : Int(max(seconds, 0).rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}
