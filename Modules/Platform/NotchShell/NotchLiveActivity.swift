import NotchCore
import SwiftUI

/// Something shown beside the closed notch for a short while: one view to the left of the
/// notch and one to the right.
public struct NotchLiveActivity {
    public let request: LiveActivityRequest
    /// The page a click on the activity opens, when the activity belongs to one.
    public let pageID: String?
    let leading: @MainActor () -> AnyView
    let trailing: @MainActor () -> AnyView
    /// A line that says more, shown under the notch while the pointer rests on it and the
    /// notch opens only on a click.
    public var peek: String?
    /// The room on each side of the notch, in the layout's points, when the activity needs less
    /// than usual (a single mark); nil for the usual room.
    public var sideWidth: CGFloat?
    /// What a sideways swipe on the closed notch does while this activity shows.
    public var onSwipe: (@MainActor (SwipeAccumulator.Direction) -> Void)?
    /// What a click on the activity does instead of opening a page, such as taking back what
    /// the notice is about; the notice goes once it is clicked.
    public var onClick: (@MainActor () -> Void)?
    /// For a notice that drops out of the notch: what the card under the notch shows. Such
    /// a notice shows nothing beside the notch.
    let drop: (@MainActor () -> AnyView)?
    /// The size the card is laid out at, before it is enlarged like the pages; nil for an
    /// activity that shows beside the notch.
    public let dropSize: CGSize?
    /// What a notice that dropped out of the notch is filled with, in place of the notch's
    /// plain black; nil for plain black.
    let dropFill: (@MainActor () -> AnyView)?
    /// A strip under the hardware notch, between the two sides, for an activity shown beside
    /// it: the closed notch grows down by `bottomHeight` to hold it. Set with `setBottom`.
    private(set) var bottom: (@MainActor () -> AnyView)?
    /// The strip's height in the layout's points; 0 without one.
    public private(set) var bottomHeight: CGFloat = 0
    /// The strip's height while the pointer is on the activity's own part (see `keepsSides`).
    public private(set) var hoveredBottomHeight: CGFloat = 0
    /// The activity's sides and its strip are its own: the pointer there does not open the
    /// notch, and the activity's views take hovering (`notchActivityIsHovered`), clicks and
    /// drags. Over the hardware notch the pointer opens it as usual.
    public var keepsSides = false

    public init<L: View, T: View>(
        id: String,
        priority: Int,
        duration: TimeInterval,
        pageID: String? = nil,
        @ViewBuilder leading: @escaping @MainActor () -> L,
        @ViewBuilder trailing: @escaping @MainActor () -> T
    ) {
        request = LiveActivityRequest(id: id, priority: priority, duration: duration)
        self.pageID = pageID
        self.leading = { AnyView(leading()) }
        self.trailing = { AnyView(trailing()) }
        drop = nil
        dropSize = nil
        dropFill = nil
    }

    /// A notice that drops out of the closed notch and goes back up after a while: the
    /// notch grows into a plate that shows it. See `AraSign` for the plate every notice uses.
    /// - Parameters:
    ///   - size: the plate's size on the sheet the pages are drawn on.
    ///   - fill: what the grown notch is filled with; nil leaves it the notch's plain black.
    public init<D: View>(
        id: String, priority: Int, duration: TimeInterval, pageID: String? = nil, dropSize size: CGSize,
        fill: (@MainActor () -> AnyView)? = nil, @ViewBuilder drop: @escaping @MainActor () -> D
    ) {
        dropFill = fill
        request = LiveActivityRequest(id: id, priority: priority, duration: duration)
        self.pageID = pageID
        leading = { AnyView(EmptyView()) }
        trailing = { AnyView(EmptyView()) }
        self.drop = { AnyView(drop()) }
        dropSize = size
    }

    /// Grows the closed notch down by `height` (in the layout's points) and draws `view` in
    /// the strip that appears under the hardware notch, where the screen has pixels.
    /// `hoveredHeight` is the strip's height while the pointer is on an activity that keeps
    /// its sides; nil keeps `height`.
    public mutating func setBottom<B: View>(
        height: CGFloat, hoveredHeight: CGFloat? = nil, @ViewBuilder _ view: @escaping @MainActor () -> B
    ) {
        bottomHeight = height
        hoveredBottomHeight = hoveredHeight ?? height
        bottom = { AnyView(view()) }
    }
}

private struct NotchActivityHoverKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The pointer is on the part of the closed notch an activity keeps for itself.
    public var notchActivityIsHovered: Bool {
        get { self[NotchActivityHoverKey.self] }
        set { self[NotchActivityHoverKey.self] = newValue }
    }
}
