import Foundation

/// How long until the next thing of the day, as a widget's chip says it: "in 40′", "in 2 h", "now".
public enum UntilNext: Equatable, Sendable {
    case now
    /// Under an hour, rounded up.
    case minutes(Int)
    /// An hour or more, in whole hours.
    case hours(Int)

    /// Nil when nothing is next.
    public static func make(next: Date?, now: Date) -> UntilNext? {
        guard let next else { return nil }
        let wait = next.timeIntervalSince(now)
        guard wait > 0 else { return .now }
        let minutes = Int((wait / 60).rounded(.up))
        return minutes < 60 ? .minutes(minutes) : .hours(minutes / 60)
    }
}
