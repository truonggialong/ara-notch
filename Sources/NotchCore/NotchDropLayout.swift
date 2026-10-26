import CoreGraphics
import Foundation

/// A notice that drops out of the closed notch: the notch grows downwards into a sign,
/// one piece with it, instead of showing something on either side.
public enum NotchDropLayout {
    /// The widest the grown notch may be, on the screen: a sign under the notch, not a bar
    /// across the screen.
    public static let maxWidth: CGFloat = 520

    /// The closed notch grown into a card.
    /// - Parameters:
    ///   - closed: the closed notch.
    ///   - card: the card as it is laid out, before it is enlarged like the pages.
    ///   - scale: how much the pages are enlarged.
    public static func shapeSize(closed: CGSize, card: CGSize, scale: CGFloat) -> CGSize {
        CGSize(
            width: min(max(closed.width, (card.width * scale).rounded()), maxWidth),
            height: closed.height + (card.height * scale).rounded())
    }

    /// Where the grown notch is on the screen, for telling a click on it: centred on the
    /// notch and hanging down from the notch's top edge.
    public static func rect(closedRect: CGRect, card: CGSize, scale: CGFloat) -> CGRect {
        let size = shapeSize(closed: closedRect.size, card: card, scale: scale)
        return CGRect(x: closedRect.midX - size.width / 2, y: closedRect.maxY - size.height, width: size.width, height: size.height)
    }
}

/// The measures of a sign: the plate a notice is written on, laid out like a wayfinding
/// sign with the name of what speaks on the left, a hairline, and the news on the right.
public enum NotchSignLayout {
    /// The widest a sign is laid out, before it is enlarged like the pages.
    public static let maxSheetWidth: CGFloat = 430

    /// The height of a line of the sign, and of the small line that may stand under it.
    public static let lineHeight: CGFloat = 15
    public static let smallLineHeight: CGFloat = 12
    /// Between two rows of the news, and above and below the sign's text.
    public static let rowSpacing: CGFloat = 5
    public static let margin: CGFloat = 9

    /// As tall as the taller of its two zones.
    /// - Parameters:
    ///   - leftHasSmallLine: the name, or the line beside it, has a small line under it.
    ///   - rowsWithSmallLine: for each row of the news, whether it has a small line under it.
    public static func height(leftHasSmallLine: Bool, rowsWithSmallLine: [Bool]) -> CGFloat {
        let left = lineHeight + (leftHasSmallLine ? smallLineHeight : 0)
        let right = rowsWithSmallLine.reduce(0) { $0 + lineHeight + ($1 ? smallLineHeight : 0) }
            + CGFloat(max(rowsWithSmallLine.count - 1, 0)) * rowSpacing
        return max(left, right) + 2 * margin
    }

    /// The two zones side by side, with the hairline between them when both have something.
    public static func width(left: CGFloat, right: CGFloat) -> CGFloat {
        min(left + (right > 0 ? right + 1 : 0), maxSheetWidth)
    }
}

/// The rays of colour a sign is lit with: three from each of its top corners, fanned towards
/// its middle like the beams of stage lights. They unroll as the sign opens, then sway and
/// brighten and dim, each in its own time, for as long as the sign shows.
public enum SignRays {
    public struct Ray: Equatable, Sendable {
        /// From the sign's top left corner, or from its top right.
        public var isLeft: Bool
        /// Degrees from straight down, towards the middle of the sign.
        public var angle: Double
        /// Its length, where 1 is its length at rest.
        public var length: Double
        /// 0…1.
        public var brightness: Double
    }

    /// Where the three rays of a corner point when they are at rest.
    public static let restAngles: [Double] = [22, 44, 64]
    /// The furthest a ray swings to either side of its rest, in degrees.
    public static let sway: Double = 7.5
    /// Seconds the rays take to unroll when the sign appears.
    public static let unrollTime: Double = 0.9

    /// Seconds each ray takes to swing there and back, and how far into its swing it starts:
    /// no two alike, so the rays are never in step.
    private static let periods: [Double] = [6.4, 8.2, 7.2, 6.8, 8.6, 7.6]
    private static let leads: [Double] = [0, 1.3, 2.2, 0.7, 2.0, 1.1]

    /// How far the rays have unrolled so many seconds after the sign appeared, 0…1: fast at
    /// first and settling, like the sign itself.
    public static func unroll(after seconds: Double) -> Double {
        let part = min(max(seconds / unrollTime, 0), 1)
        return 1 - pow(1 - part, 3)
    }

    /// The rays so many seconds after the sign appeared: the left corner's three, then the
    /// right corner's.
    public static func rays(after seconds: Double) -> [Ray] {
        let time = max(seconds, 0)
        let unrolled = unroll(after: time)
        return periods.indices.map { index in
            let swing = sin(2 * .pi * (time + leads[index]) / periods[index])
            return Ray(
                isLeft: index < restAngles.count,
                angle: restAngles[index % restAngles.count] + sway * swing,
                length: (0.1 + 0.9 * unrolled) * (0.95 + 0.13 * swing),
                brightness: unrolled * (0.73 + 0.27 * swing))
        }
    }

    /// How one ray swings back and forth once it has unrolled: between the ends of each range,
    /// there and back in `period` seconds, starting `lead` seconds into its swing. The sign
    /// hands this to Core Animation, which plays it without the app drawing anything.
    public struct Swing: Equatable, Sendable {
        public let angles: ClosedRange<Double>
        public let lengths: ClosedRange<Double>
        public let brightness: ClosedRange<Double>
        public let period: Double
        public let lead: Double
    }

    public static func swing(of index: Int) -> Swing {
        let rest = restAngles[index % restAngles.count]
        return Swing(
            angles: (rest - sway)...(rest + sway),
            lengths: (0.95 - 0.13)...(0.95 + 0.13),
            brightness: (0.73 - 0.27)...(0.73 + 0.27),
            period: periods[index % periods.count],
            lead: leads[index % leads.count])
    }

    /// The rays standing still, for when the Mac is set to reduce motion.
    public static let still: [Ray] = periods.indices.map { index in
        Ray(isLeft: index < restAngles.count, angle: restAngles[index % restAngles.count], length: 1, brightness: 0.8)
    }
}

/// The measures of one ray of a sign, drawn once as a blurred picture and then only turned,
/// stretched and dimmed while it moves: blurring the rays again for every frame cost a fifth
/// to a third of a processor core for as long as a sign showed.
public struct SignRayLayout: Equatable, Sendable {
    /// How long a ray at rest is, and how wide: from the sign's width.
    public let length: CGFloat
    public let breadth: CGFloat
    /// How much the ray is blurred, in points.
    public let blur: CGFloat = 7
    /// The size of the sign the rays light, below the notch.
    public let signSize: CGSize

    public init(signSize: CGSize) {
        self.signSize = signSize
        length = signSize.width * 0.75
        breadth = max(signSize.width * 0.1, 34)
    }

    /// Room round the blade for its blur to fade out in.
    public var margin: CGFloat {
        (blur * 3).rounded(.up)
    }

    /// The picture of one ray: the blade, which starts a little above where it hangs from,
    /// with room for its blur all round.
    public var imageSize: CGSize {
        CGSize(width: breadth + 2 * margin, height: length * 1.08 + 2 * margin)
    }

    /// Where the ray hangs from inside its picture, as a fraction of the picture.
    public var anchor: CGPoint {
        CGPoint(x: 0.5, y: (margin + length * 0.08) / imageSize.height)
    }

    /// Where the ray hangs from on the sign: just above its top left or top right corner.
    public func pivot(isLeft: Bool) -> CGPoint {
        CGPoint(x: isLeft ? 0 : signSize.width, y: -signSize.height * 0.12)
    }
}

/// Where a click on what shows of the closed notch lands. The closed notch's window lets every
/// click through, so as not to stand in the way of the menu bar; while something shows on it,
/// a window of exactly this area takes the clicks, so that a click on a sign is the sign's and
/// does not also land in the app underneath.
public enum NotchClickArea {
    /// A sign is clicked where its card is; something beside the notch, on either side of it.
    public static func rect(closedRect: CGRect, dropCard: CGSize?, sideWidth: CGFloat, scale: CGFloat) -> CGRect {
        dropCard.map { NotchDropLayout.rect(closedRect: closedRect, card: $0, scale: scale) }
            ?? closedRect.insetBy(dx: -sideWidth, dy: 0)
    }

    /// Only while something shows on the closed notch: open, the notch's own window takes the
    /// clicks; with nothing on it, the menu bar has them.
    public static func takesClicks(isOpen: Bool, showsSomething: Bool, isHidden: Bool) -> Bool {
        !isOpen && showsSomething && !isHidden
    }
}
