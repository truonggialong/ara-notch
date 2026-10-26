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
}
