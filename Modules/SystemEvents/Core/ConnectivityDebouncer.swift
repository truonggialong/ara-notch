import Foundation

public enum ConnectivityEvent: Equatable, Sendable {
    case offline
    case online
}

/// Reports a lost connection only once it has stayed lost for a few seconds, so a flickering
/// Wi-Fi link is not announced. Coming back online after a reported loss is announced at once.
public struct ConnectivityDebouncer: Sendable {
    public static let offlineDelay: TimeInterval = 3

    private var offlineSince: Date?
    private var hasReportedOffline = false

    public init() {}

    /// When `advance` should be called to learn whether the loss has lasted long enough.
    public var nextDeadline: Date? {
        hasReportedOffline ? nil : offlineSince?.addingTimeInterval(Self.offlineDelay)
    }

    public mutating func update(isOnline: Bool, at now: Date) -> ConnectivityEvent? {
        if isOnline {
            let wasReported = hasReportedOffline
            offlineSince = nil
            hasReportedOffline = false
            return wasReported ? .online : nil
        }
        if offlineSince == nil {
            offlineSince = now
            return nil
        }
        return advance(to: now)
    }

    public mutating func advance(to now: Date) -> ConnectivityEvent? {
        guard let deadline = nextDeadline, now >= deadline else { return nil }
        hasReportedOffline = true
        return .offline
    }
}
