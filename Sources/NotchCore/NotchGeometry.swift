import CoreGraphics

/// How the notch is drawn on a display that has no hardware notch.
public enum NotchStyle: String, Sendable {
    /// A notch shape stuck to the top edge, in the menu bar.
    case attached
    /// A capsule floating just below the menu bar.
    case pill
}

/// Rectangles of the notch on one display, in global coordinates with a bottom-left origin.
public struct NotchGeometry: Equatable, Sendable {
    public static let pillHeight: CGFloat = 30
    /// Space between the menu bar and the pill.
    public static let pillGap: CGFloat = 6

    public static let virtualNotchWidth: CGFloat = 180
    public static let minimumVirtualNotchHeight: CGFloat = 24
    /// The bar the notch waits as on a display that has no hardware notch.
    public static let idleBarSize = CGSize(width: 150, height: 10)
    public static let hoverPadding: CGFloat = 4
    public static let defaultOpenSize = CGSize(width: 640, height: 200)
    /// Width of the area on each side of the notch used by a live activity.
    public static let defaultActivitySideWidth: CGFloat = 92

    public let screen: ScreenDescriptor
    public let style: NotchStyle

    public init(screen: ScreenDescriptor, style: NotchStyle = .attached) {
        self.screen = screen
        self.style = style
    }

    /// A hardware notch cannot float, so the pill style only applies where there is none.
    public var isPill: Bool {
        style == .pill && !hasPhysicalNotch
    }

    public var hasPhysicalNotch: Bool {
        screen.safeAreaTop > 0 && screen.auxLeftWidth != nil && screen.auxRightWidth != nil
    }

    public var closedRect: CGRect {
        let frame = screen.frame
        if hasPhysicalNotch, let left = screen.auxLeftWidth, let right = screen.auxRightWidth {
            return CGRect(
                x: frame.minX + left,
                y: frame.maxY - screen.safeAreaTop,
                width: frame.width - left - right,
                height: screen.safeAreaTop)
        }
        if isPill {
            return CGRect(
                x: frame.midX - Self.virtualNotchWidth / 2,
                y: frame.maxY - screen.menuBarHeight - Self.pillGap - Self.pillHeight,
                width: Self.virtualNotchWidth,
                height: Self.pillHeight)
        }
        let height = max(screen.menuBarHeight, Self.minimumVirtualNotchHeight)
        return CGRect(
            x: frame.midX - Self.virtualNotchWidth / 2,
            y: frame.maxY - height,
            width: Self.virtualNotchWidth,
            height: height)
    }

    /// On a display with nothing cut out of it, the notch stuck to the top edge has no need
    /// to be the size of a hardware notch while it has nothing to show: it waits as a thin bar.
    public var restsAsBar: Bool {
        !hasPhysicalNotch && !isPill
    }

    /// The closed notch while it waits: untouched and with nothing beside it.
    public var idleRect: CGRect {
        guard restsAsBar else { return closedRect }
        let size = Self.idleBarSize
        return CGRect(x: closedRect.midX - size.width / 2, y: closedRect.maxY - size.height, width: size.width, height: size.height)
    }

    /// Padded on every side; the part above the screen keeps a pointer on the top edge inside.
    public var hoverRect: CGRect {
        hoverRect(padding: Self.hoverPadding)
    }

    /// The closed notch grown by `padding` points on every side: where hovering, clicking and
    /// swiping reach the closed notch.
    public func hoverRect(padding: CGFloat) -> CGRect {
        closedRect.insetBy(dx: -max(0, padding), dy: -max(0, padding))
    }

    /// Where the closed notch is reached. Asleep (waiting as a bar), only on the bar, so the
    /// menu bar under it stays free; awake (touched, or showing something), over its full size,
    /// which holds the bar, so the pointer that woke it is still on it.
    public func hoverRect(padding: CGFloat, isAwake: Bool) -> CGRect {
        isAwake ? hoverRect(padding: padding) : idleRect.insetBy(dx: -max(0, padding), dy: -max(0, padding))
    }

    /// How far to the sides of the closed notch, and below it, dragged files already open it.
    public static let dragReach = CGSize(width: 80, height: 64)

    /// Where files being dragged open the notch. Larger than the notch itself: at the very
    /// top edge of the screen macOS answers a drag with Mission Control, so the notch has to
    /// open before the pointer gets there.
    public var dragRect: CGRect {
        CGRect(
            x: closedRect.minX - Self.dragReach.width, y: closedRect.minY - Self.dragReach.height,
            width: closedRect.width + 2 * Self.dragReach.width, height: closedRect.height + Self.dragReach.height)
    }

    public func openRect(size: CGSize = NotchGeometry.defaultOpenSize) -> CGRect {
        let frame = screen.frame
        let idealX = closedRect.midX - size.width / 2
        let maxX = max(frame.maxX - size.width, frame.minX)
        let x = min(max(idealX, frame.minX), maxX)
        // The panel grows down from the top of the closed shape: the screen's top edge, or the pill's.
        return CGRect(x: x, y: closedRect.maxY - size.height, width: size.width, height: size.height)
    }

    /// The closed notch widened on both sides to make room for a live activity.
    public func compactRect(sideWidth: CGFloat = NotchGeometry.defaultActivitySideWidth) -> CGRect {
        closedRect.insetBy(dx: -sideWidth, dy: 0)
    }

    /// The top strip of the open panel, as tall as the notch, holding the tabs.
    public func headerRect(size: CGSize = NotchGeometry.defaultOpenSize) -> CGRect {
        let open = openRect(size: size)
        let height = closedRect.height
        return CGRect(x: open.minX, y: open.maxY - height, width: open.width, height: height)
    }

    public func openHitRect(size: CGSize = NotchGeometry.defaultOpenSize) -> CGRect {
        var rect = openRect(size: size)
        rect.size.height += Self.hoverPadding
        return rect
    }

    /// True when the open panel, going from one size to a smaller one, leaves a pointer that
    /// was on it outside. The pointer has not left then: the panel went from under it.
    public func shrinkingLeavesOutside(_ pointer: CGPoint, from old: CGSize, to new: CGSize) -> Bool {
        openHitRect(size: old).contains(pointer) && !openHitRect(size: new).contains(pointer)
    }
}

/// How large the notch is shown. Its pages are laid out on a sheet of `defaultOpenSize` and
/// shown enlarged as a whole, so text, icons and spacing all grow together.
public enum NotchSize: String, CaseIterable, Sendable {
    /// The size the layout is drawn at: small text, for those who want the notch out of the way.
    case compact
    /// A tenth larger: the usual size until 0.11.0.
    case regular
    /// A quarter larger: the usual size. A fifth larger was the usual one from 0.11.0 to
    /// 0.22.2; it was too close to this one to be told apart, and reads as this one now.
    case large
    /// Half as large again.
    case extraLarge

    /// The size in use until the user chooses another.
    public static let standard = NotchSize.large

    /// The size stored under a name, including the one that is gone.
    public init?(storedName: String) {
        if storedName == "comfortable" {
            self = .large
        } else {
            self.init(rawValue: storedName)
        }
    }

    /// How much larger than the sheet the pages are laid out on, in both directions.
    public var scale: CGFloat {
        switch self {
        case .compact: 1
        case .regular: 1.1
        case .large: 1.25
        case .extraLarge: 1.5
        }
    }

    public var openSize: CGSize {
        let base = NotchGeometry.defaultOpenSize
        return CGSize(width: (base.width * scale).rounded(), height: (base.height * scale).rounded())
    }

    /// How much the row of tabs and the live activities grow. They sit beside the hardware
    /// notch, which is as tall as it is whatever the size chosen, so this stops at 1.3.
    public var edgeScale: CGFloat {
        min(scale, 1.3)
    }

    /// The room a live activity has on each side of the closed notch.
    public var activitySideWidth: CGFloat {
        (NotchGeometry.defaultActivitySideWidth * edgeScale).rounded()
    }
}

/// How tall the open notch is for a page that asks for more room than the usual sheet. The
/// notch grows downwards only; its width is the same for every page.
public enum PageHeight {
    /// The most of the screen's height the open notch may take.
    public static let maximumShare: CGFloat = 0.8

    /// - Parameter sheetHeight: the height of sheet the page asks for, before enlargement;
    ///   nil for the usual one.
    public static func open(sheetHeight: CGFloat?, size: NotchSize, screenHeight: CGFloat) -> CGFloat {
        let usual = size.openSize.height
        guard let sheetHeight else { return usual }
        let most = max(usual, (screenHeight * maximumShare).rounded())
        return min(max((sheetHeight * size.scale).rounded(), usual), most)
    }
}
