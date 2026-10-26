import CoreGraphics

/// Plain measurements of one display, in global coordinates with a bottom-left origin.
public struct ScreenDescriptor: Equatable, Sendable {
    public var frame: CGRect
    public var safeAreaTop: CGFloat
    /// Width of the unobscured area to the left of the notch; nil when the display has no notch.
    public var auxLeftWidth: CGFloat?
    /// Width of the unobscured area to the right of the notch; nil when the display has no notch.
    public var auxRightWidth: CGFloat?
    public var menuBarHeight: CGFloat

    public init(
        frame: CGRect,
        safeAreaTop: CGFloat,
        auxLeftWidth: CGFloat?,
        auxRightWidth: CGFloat?,
        menuBarHeight: CGFloat
    ) {
        self.frame = frame
        self.safeAreaTop = safeAreaTop
        self.auxLeftWidth = auxLeftWidth
        self.auxRightWidth = auxRightWidth
        self.menuBarHeight = menuBarHeight
    }
}
