import Foundation

/// Copy several things, then paste them one after another: while the stack is active every
/// copy is added to it and every paste takes the next clip.
public struct CopyStack: Equatable, Sendable {
    public enum Order: String, CaseIterable, Sendable {
        case firstCopiedFirst
        case lastCopiedFirst
    }

    public var order: Order
    public private(set) var isActive = false
    /// Ids of the stacked clips, in the order they were copied.
    public private(set) var itemIDs: [Int64] = []

    public init(order: Order = .firstCopiedFirst) {
        self.order = order
    }

    public var count: Int {
        itemIDs.count
    }

    /// The clip the next paste will take.
    public var peek: Int64? {
        order == .firstCopiedFirst ? itemIDs.first : itemIDs.last
    }

    /// Starts collecting, with an empty stack.
    public mutating func start() {
        itemIDs = []
        isActive = true
    }

    public mutating func stop() {
        itemIDs = []
        isActive = false
    }

    /// Adds a freshly copied clip. Ignored while the stack is not active.
    public mutating func push(_ id: Int64) {
        guard isActive else { return }
        itemIDs.append(id)
    }

    /// Takes the clip for the paste that is about to happen. Nil means an ordinary paste: the
    /// stack is not active or still empty. Taking the last clip ends the stack.
    public mutating func next() -> Int64? {
        guard isActive, !itemIDs.isEmpty else { return nil }
        let id = order == .firstCopiedFirst ? itemIDs.removeFirst() : itemIDs.removeLast()
        if itemIDs.isEmpty {
            isActive = false
        }
        return id
    }

    /// Drops a clip that no longer exists.
    public mutating func remove(_ id: Int64) {
        itemIDs.removeAll { $0 == id }
    }
}
