import Foundation

/// What the Library window lists: everything, or the clips of one kind, source app or board.
public enum LibraryFilter: Hashable, Sendable {
    case all
    case kind(ClipKind)
    /// Clips copied from the app with this name.
    case app(String)
    case board(Int64)

    public func matches(_ item: ClipItem, membership: [Int64: Set<Int64>]) -> Bool {
        switch self {
        case .all: true
        case .kind(let kind): item.kind == kind
        case .app(let name): item.source.appName == name
        case .board(let id): membership[item.id]?.contains(id) ?? false
        }
    }

    /// The clips this filter lists, in their given order, narrowed by a search.
    public func items(from items: [ClipItem], membership: [Int64: Set<Int64>], search: String) -> [ClipItem] {
        let query = ClipQuery(search)
        return items.filter { matches($0, membership: membership) && (query.isEmpty || query.matches($0)) }
    }
}

/// The Library's sidebar: every filter that lists at least something, with how many clips.
public struct LibrarySidebar: Equatable, Sendable {
    public struct Entry: Equatable, Identifiable, Sendable {
        public var filter: LibraryFilter
        /// The kind's raw value, the app's name, or the board's name.
        public var title: String
        /// SF Symbol of a board.
        public var symbolName: String?
        public var count: Int
        /// A board whose clips open only with the vault's passcode.
        public var isLocked: Bool

        public var id: LibraryFilter { filter }

        public init(filter: LibraryFilter, title: String, symbolName: String? = nil, count: Int, isLocked: Bool = false) {
            self.filter = filter
            self.title = title
            self.symbolName = symbolName
            self.count = count
            self.isLocked = isLocked
        }
    }

    public var total: Int
    /// Kinds that occur, in the order of `ClipKind`.
    public var kinds: [Entry]
    /// Source apps, the most used first.
    public var apps: [Entry]
    /// Boards in creation order, empty and locked ones included.
    public var boards: [Entry]

    /// - Parameter items: the plain history; vault clips are not part of the Library.
    public init(items: [ClipItem], boards: [ClipBoard], membership: [Int64: Set<Int64>]) {
        total = items.count

        let perKind = Dictionary(grouping: items, by: \.kind).mapValues(\.count)
        kinds = ClipKind.allCases.compactMap { kind in
            perKind[kind].map { Entry(filter: .kind(kind), title: kind.rawValue, count: $0) }
        }

        let perApp = Dictionary(grouping: items.compactMap(\.source.appName), by: { $0 }).mapValues(\.count)
        apps = perApp
            .sorted { ($1.value, $0.key) < ($0.value, $1.key) }
            .map { Entry(filter: .app($0.key), title: $0.key, count: $0.value) }

        self.boards = boards.map { board in
            // A locked board's clips are not in the plain history: its own count stands.
            Entry(
                filter: .board(board.id), title: board.name, symbolName: board.symbolName,
                count: board.isLocked ? board.itemCount : items.count { membership[$0.id]?.contains(board.id) ?? false },
                isLocked: board.isLocked)
        }
    }

    public func contains(_ filter: LibraryFilter) -> Bool {
        filter == .all || (kinds + apps + boards).contains { $0.filter == filter }
    }
}
