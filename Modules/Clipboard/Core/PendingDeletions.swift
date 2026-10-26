import Foundation

/// Clips the user deleted a moment ago. They are hidden at once but really deleted only after
/// a few seconds, so the deletion can be taken back.
public struct PendingDeletions: Equatable, Sendable {
    /// How long a deletion can be undone.
    public static let window: TimeInterval = 8
    /// Deletions closer together than this are one action, such as a selection deleted in
    /// the Library, and come back together.
    static let sameAction: TimeInterval = 0.5

    private struct Batch: Equatable, Sendable {
        var ids: [Int64]
        var addedAt: Date
    }

    private var batches: [Batch] = []

    public init() {}

    /// The clips to leave out of every list.
    public var hiddenIDs: Set<Int64> {
        Set(batches.flatMap(\.ids))
    }

    /// How many clips the most recent deletion took.
    public var latestCount: Int {
        batches.last?.ids.count ?? 0
    }

    /// When the oldest deletion can no longer be undone.
    public var nextDeadline: Date? {
        batches.first.map { $0.addedAt.addingTimeInterval(Self.window) }
    }

    public mutating func add(_ ids: [Int64], at now: Date) {
        let hidden = hiddenIDs
        let fresh = ids.filter { !hidden.contains($0) }
        guard !fresh.isEmpty else { return }
        if let last = batches.indices.last, now.timeIntervalSince(batches[last].addedAt) < Self.sameAction {
            batches[last].ids += fresh
        } else {
            batches.append(Batch(ids: fresh, addedAt: now))
        }
    }

    /// Takes back the most recent deletion and returns its clips.
    public mutating func undoLast() -> [Int64] {
        batches.popLast()?.ids ?? []
    }

    /// The clips whose time to be undone has passed: these are to be deleted for real.
    public mutating func takeDue(at now: Date) -> [Int64] {
        let due = batches.filter { now.timeIntervalSince($0.addedAt) >= Self.window }
        batches.removeAll { now.timeIntervalSince($0.addedAt) >= Self.window }
        return due.flatMap(\.ids)
    }

    /// Everything still waiting, for when there will be no later: the app is quitting.
    public mutating func takeAll() -> [Int64] {
        defer { batches = [] }
        return batches.flatMap(\.ids)
    }
}
