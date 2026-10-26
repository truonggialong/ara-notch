import Foundation

/// How big a widget is drawn, in cells of the grid it stands on: small is one cell, wide two
/// side by side, large two by two. Each feature draws its widget for the size it is given.
public enum WidgetSize: String, CaseIterable, Sendable {
    case small, wide, large

    public var columns: Int {
        self == .small ? 1 : 2
    }

    public var rows: Int {
        self == .large ? 2 : 1
    }

    /// The size the tile's size button goes to: small, wide, large, then small again.
    public var next: WidgetSize {
        switch self {
        case .small: .wide
        case .wide: .large
        case .large: .small
        }
    }
}
