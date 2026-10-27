import Foundation

/// Whether the track rests beside the closed notch: while it plays, and for a while after it
/// was paused, so a short pause does not take it away.
public struct PausedResting: Equatable, Sendable {
    /// How long a paused track stays beside the notch.
    public static let lingering: TimeInterval = 5 * 60

    private var isPlaying = false
    private var pausedAt: Date?

    public init() {}

    /// The player was last reported playing or paused at `date`.
    public mutating func update(isPlaying: Bool, at date: Date) {
        if isPlaying {
            pausedAt = nil
        } else if self.isPlaying {
            // Only a pause seen happening counts: a track found paused was not just playing.
            pausedAt = date
        }
        self.isPlaying = isPlaying
    }

    /// Nothing is playing any more, or the reading stopped.
    public mutating func reset() {
        isPlaying = false
        pausedAt = nil
    }

    public func shows(at date: Date) -> Bool {
        if isPlaying { return true }
        guard let hideDate else { return false }
        return date < hideDate
    }

    /// When a paused track leaves; nil while playing or when it is not shown.
    public var hideDate: Date? {
        pausedAt.map { $0.addingTimeInterval(Self.lingering) }
    }
}
