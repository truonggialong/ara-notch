import NotchCore
import SwiftUI

/// State the notch views render from. Owned and mutated by `NotchController`.
@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var registry = PageRegistry()
    @Published var closedSize = CGSize(width: NotchGeometry.virtualNotchWidth, height: 32)
    /// The size the closed notch waits at while untouched and with nothing beside it, when
    /// that is smaller than the notch: a thin bar on a display with no hardware notch.
    @Published var idleSize: CGSize?
    @Published var openSize = NotchGeometry.defaultOpenSize
    /// How much larger than their layout the pages are shown, and how much the tab row and
    /// the live activities, which have only the height of the hardware notch to grow in.
    @Published var scale: CGFloat = 1
    @Published var edgeScale: CGFloat = 1
    @Published var hasPhysicalNotch = false
    /// The notch is drawn as a floating capsule (a display without a hardware notch, pill style on).
    @Published var isPill = false
    /// The live activity to show beside the notch while it is closed.
    @Published var activity: NotchLiveActivity?
    /// The activity is one that rests beside the notch (the track playing), not a notice.
    @Published var activityIsResting = false
    /// An app is full screen on this display: the notch keeps out of its way.
    @Published var isHiddenForFullScreen = false
    @Published var activitySideWidth = NotchGeometry.defaultActivitySideWidth

    /// The room on each side of the notch for the activity showing: its own, grown with the
    /// notch's edge, or the usual.
    var shownActivitySideWidth: CGFloat {
        activity?.sideWidth.map { ($0 * edgeScale).rounded() } ?? activitySideWidth
    }

    /// The strip under the hardware notch for the activity showing beside it, grown with the
    /// notch's edge; 0 when it has none.
    var shownActivityBottomHeight: CGFloat {
        guard let activity, activity.dropSize == nil, activity.bottom != nil else { return 0 }
        let height = isActivityHovered ? activity.hoveredBottomHeight : activity.bottomHeight
        return (height * edgeScale).rounded()
    }

    /// The pointer is on the closed notch: it swells a little to say it was touched.
    @Published var isTouched = false
    /// The pointer is on the sides or strip of an activity that keeps them for itself.
    @Published var isActivityHovered = false
    /// The closed notch may show its activity's extra line while touched.
    @Published var allowsPeek = false
    /// The notice on show is about to go: what is on it fades before the plate shrinks.
    @Published var isNoticeLeaving = false
    /// The user pinned the open panel: it stays until unpinned.
    @Published var isPinned = false

    var pages: [String: NotchPage] = [:]
    var onOpenSettings: (() -> Void)?
    var onTogglePin: (() -> Void)?
}
