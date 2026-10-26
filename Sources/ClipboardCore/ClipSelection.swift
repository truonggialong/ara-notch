/// The highlighted entry of a list of clips, tracked by id so it survives reordering and filtering.
public struct ClipSelection: Equatable, Sendable {
    public private(set) var selectedID: Int64?

    public init() {}

    /// Call when the list changes: keeps the selection if it is still listed, otherwise selects
    /// the first entry (or nothing when the list is empty).
    public mutating func sync(with ids: [Int64]) {
        if let selectedID, ids.contains(selectedID) { return }
        selectedID = ids.first
    }

    public mutating func moveNext(in ids: [Int64]) {
        move(by: 1, in: ids)
    }

    public mutating func movePrevious(in ids: [Int64]) {
        move(by: -1, in: ids)
    }

    /// Selects the entry at this position. Returns false, changing nothing, when out of range.
    @discardableResult
    public mutating func select(index: Int, in ids: [Int64]) -> Bool {
        guard ids.indices.contains(index) else { return false }
        selectedID = ids[index]
        return true
    }

    public mutating func select(id: Int64, in ids: [Int64]) {
        guard ids.contains(id) else { return }
        selectedID = id
    }

    public func index(in ids: [Int64]) -> Int? {
        selectedID.flatMap(ids.firstIndex(of:))
    }

    /// Stops at both ends rather than wrapping around.
    private mutating func move(by offset: Int, in ids: [Int64]) {
        guard let current = index(in: ids) else {
            selectedID = ids.first
            return
        }
        selectedID = ids[min(max(current + offset, 0), ids.count - 1)]
    }
}
