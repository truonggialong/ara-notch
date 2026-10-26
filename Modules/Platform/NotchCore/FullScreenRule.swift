import CoreGraphics

/// When an app is full screen on a display (a video, a presentation), the notch on that
/// display gets out of the way; a notice still drops out of it for its few seconds.
public enum FullScreenRule {
    /// A window on screen, as the window list gives it.
    public struct Window: Equatable, Sendable {
        /// Measured from the top left of the main display.
        public var bounds: CGRect
        /// 0 for ordinary windows; the menu bar, the Dock and the like sit higher.
        public var layer: Int
        /// One of this app's own windows.
        public var isOwn: Bool

        public init(bounds: CGRect, layer: Int, isOwn: Bool) {
            self.bounds = bounds
            self.layer = layer
            self.isOwn = isOwn
        }
    }

    /// The indexes of the displays an ordinary window of another app covers whole, menu bar
    /// and all, as a full-screen window does. Display frames are measured as window bounds are.
    public static func coveredDisplays(windows: [Window], displays: [CGRect]) -> Set<Int> {
        var covered: Set<Int> = []
        for window in windows where window.layer == 0 && !window.isOwn {
            for (index, display) in displays.enumerated() where same(window.bounds, display) {
                covered.insert(index)
            }
        }
        return covered
    }

    /// Whether the notch on a covered display is hidden now.
    public static func hidesNotch(isCovered: Bool, isEnabled: Bool, isOpen: Bool, showsNotice: Bool) -> Bool {
        isCovered && isEnabled && !isOpen && !showsNotice
    }

    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
    }
}
