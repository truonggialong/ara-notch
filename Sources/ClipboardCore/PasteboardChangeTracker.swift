/// Decides when the pasteboard should be read, given its change counter.
///
/// Apps often clear the pasteboard and fill it a moment later. The counter moves at the clear,
/// so a read at that instant finds nothing; such a read is retried on the next polls.
public struct PasteboardChangeTracker: Sendable {
    public static let maxRetries = 2

    private var lastChangeCount: Int
    private var retriesLeft = 0
    private var isRetryPending = false

    public init(changeCount: Int) {
        lastChangeCount = changeCount
    }

    /// Call on every poll. True means: read the pasteboard now, then call `readFinished`.
    public mutating func shouldRead(changeCount: Int) -> Bool {
        if changeCount != lastChangeCount {
            lastChangeCount = changeCount
            retriesLeft = Self.maxRetries
            isRetryPending = false
            return true
        }
        return isRetryPending
    }

    public mutating func readFinished(foundContent: Bool) {
        if foundContent || retriesLeft == 0 {
            isRetryPending = false
        } else {
            retriesLeft -= 1
            isRetryPending = true
        }
    }

    /// Call after this app wrote to the pasteboard, so its own write is not read back.
    public mutating func ignore(changeCount: Int) {
        lastChangeCount = changeCount
        isRetryPending = false
    }
}
