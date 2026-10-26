import Foundation

/// Where a tooltip goes on screen, in AppKit's coordinates (y grows upwards).
public enum TooltipPlacement {
    /// The tooltip's bottom-left corner: centred below its button, above it when the screen
    /// ends first, and never off the sides.
    public static func origin(anchor: CGRect, size: CGSize, screen: CGRect, gap: CGFloat = 6, margin: CGFloat = 4) -> CGPoint {
        var y = anchor.minY - gap - size.height
        if y < screen.minY + margin {
            y = anchor.maxY + gap
        }
        let x = min(max(anchor.midX - size.width / 2, screen.minX + margin), screen.maxX - size.width - margin)
        return CGPoint(x: x, y: y)
    }
}

/// A key the open notch acts on when it was opened from the keyboard.
public enum NotchKey: Equatable, Sendable {
    case left, right, up, down
    case confirm, space, delete, escape
    case nextPage, previousPage

    public init?(keyCode: UInt16, isShiftDown: Bool) {
        switch keyCode {
        case 123: self = .left
        case 124: self = .right
        case 126: self = .up
        case 125: self = .down
        case 36, 76: self = .confirm
        case 49: self = .space
        case 51: self = .delete
        case 53: self = .escape
        case 48: self = isShiftDown ? .previousPage : .nextPage
        default: return nil
        }
    }

    /// While a text field in the notch has the keys, only the keys that leave it are taken;
    /// the rest belong to the text.
    public var worksWhileTyping: Bool {
        self == .escape || self == .nextPage || self == .previousPage
    }
}
