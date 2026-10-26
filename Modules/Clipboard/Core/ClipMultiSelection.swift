import Foundation

/// Which clips of a list are selected, the way a file list selects: a click picks one,
/// Command-click adds or removes one, Shift-click picks a range.
public struct ClipMultiSelection: Equatable, Sendable {
    public private(set) var ids: Set<Int64> = []
    /// The clip most recently added to the selection; details are shown for it.
    public private(set) var primary: Int64?
    /// Where a Shift-click range starts.
    private var anchor: Int64?

    public init() {}

    /// - Parameters:
    ///   - order: the ids of the listed clips, top to bottom.
    ///   - extending: Shift is held.
    ///   - toggling: Command is held.
    public mutating func click(_ id: Int64, in order: [Int64], extending: Bool = false, toggling: Bool = false) {
        guard let index = order.firstIndex(of: id) else { return }
        if extending {
            let start = anchor.flatMap(order.firstIndex(of:)) ?? 0
            ids = Set(order[min(start, index)...max(start, index)])
            anchor = order[start]
            primary = id
        } else if toggling {
            if ids.contains(id) {
                ids.remove(id)
                if primary == id {
                    primary = order.last { ids.contains($0) }
                }
            } else {
                ids.insert(id)
                primary = id
            }
            anchor = id
        } else {
            ids = [id]
            primary = id
            anchor = id
        }
    }

    /// Forgets clips that are no longer listed.
    /// Selects every clip in the list; the first becomes the one shown in detail.
    public mutating func selectAll(in order: [Int64]) {
        ids = Set(order)
        primary = order.first
        anchor = order.first
    }

    public mutating func sync(with order: [Int64]) {
        ids.formIntersection(order)
        if let current = primary, !ids.contains(current) {
            primary = order.last { ids.contains($0) }
        }
        if let current = anchor, !order.contains(current) {
            anchor = nil
        }
    }

    /// The selected ids in list order.
    public func ordered(in order: [Int64]) -> [Int64] {
        order.filter(ids.contains)
    }

    /// What a drag starting on this clip carries: the whole selection when the clip is part
    /// of it, otherwise just the clip.
    public func dragged(from id: Int64, in order: [Int64]) -> [Int64] {
        ids.contains(id) && ids.count > 1 ? ordered(in: order) : [id]
    }

    /// Clip ids as carried by a drag inside the app.
    public static func encode(_ ids: [Int64]) -> String {
        ids.map(String.init).joined(separator: ",")
    }

    public static func decode(_ text: String) -> [Int64] {
        text.split(separator: ",").compactMap { Int64($0.trimmingCharacters(in: .whitespaces)) }
    }
}
