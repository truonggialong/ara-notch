import Foundation

/// What one pixel row of a frame looks like: how bright it is, on average, in each of several
/// column bands. Brightness, not a hash of the pixels: an app does not draw the same content to
/// the very same pixel values after a scroll, so rows have to be compared with some give.
/// Two rows match when most bands are close, so a change in one narrow place (a caret, a
/// spelling underline drawn a moment late) does not make the whole row a different one.
public struct RowSignature: Equatable, Sendable, ExpressibleByIntegerLiteral {
    /// Two bands this close in level count as the same.
    public static let bandTolerance: UInt64 = 8

    public var bands: [UInt64]

    public init(bands: [UInt64]) {
        self.bands = bands
    }

    /// A row described by a single level.
    public init(_ value: UInt64) {
        bands = [value]
    }

    public init(integerLiteral value: UInt64) {
        bands = [value]
    }

    /// Up to a quarter of the bands may differ.
    public func matches(_ other: RowSignature) -> Bool {
        guard let differing = differingBands(from: other) else { return false }
        return differing <= bands.count / 4
    }

    /// How many bands are further apart than the tolerance; nil when the two rows are not
    /// split the same way.
    public func differingBands(from other: RowSignature) -> Int? {
        guard bands.count == other.bands.count else { return nil }
        var differing = 0
        for index in bands.indices where Self.gap(bands[index], other.bands[index]) > Self.bandTolerance {
            differing += 1
        }
        return differing
    }

    /// The band differences added up; nil when the two rows are not split the same way.
    public func distance(to other: RowSignature) -> Double? {
        guard bands.count == other.bands.count else { return nil }
        var total = 0.0
        for index in bands.indices {
            total += Double(Self.gap(bands[index], other.bands[index]))
        }
        return total
    }

    private static func gap(_ a: UInt64, _ b: UInt64) -> UInt64 {
        a > b ? a - b : b - a
    }
}

/// Joins the frames of a scrolling capture into one tall picture. A frame is described by one
/// signature per pixel row, so two frames can be compared row by row.
public struct ScrollStitcher: Sendable {
    public enum Addition: Equatable, Sendable {
        /// The first frame: all of it is kept.
        case first
        /// The page moved; this many rows at the bottom of the frame are new.
        case appended(newRows: Int)
        /// The frame shows what the last one did: the page has reached its end.
        case noMovement
        /// The page moved the other way: the frame shows what lies above the last one.
        case movedBack
        /// The frame could not be matched to the last one.
        case lost
    }

    /// At least this share of a frame must still be on screen in the next one to trust the match.
    static let minimumOverlap = 0.1
    /// Up to this share of the compared rows may differ: a blinking caret, a fading scroll bar,
    /// and things an app draws a moment after a scroll, such as spelling underlines.
    static let tolerance = 0.2

    public let maximumRows: Int
    public private(set) var totalRows = 0
    private var last: [RowSignature]?

    public init(maximumRows: Int = 30_000) {
        self.maximumRows = maximumRows
    }

    /// The picture has reached its greatest height; further frames add nothing.
    public var isFull: Bool { totalRows >= maximumRows }

    public mutating func add(_ rows: [RowSignature]) -> Addition {
        guard let last else {
            self.last = rows
            totalRows = min(rows.count, maximumRows)
            return .first
        }
        guard let shift = Self.shift(from: last, to: rows) else {
            // Not below the last frame; above it, perhaps. The last frame stays the reference.
            if let back = Self.shift(from: rows, to: last), back > 0 { return .movedBack }
            return .lost
        }
        guard shift > 0 else { return .noMovement }
        let newRows = min(shift, maximumRows - totalRows)
        totalRows += newRows
        self.last = rows
        return .appended(newRows: newRows)
    }

    /// How many rows the page moved up between two frames of the same height: the shift at
    /// which the lower part of the first frame best matches the upper part of the second.
    /// Zero when they show the same; nil when no shift matches well enough.
    ///
    /// A shift is passable when few enough rows fail to match. Among passable shifts the one
    /// whose rows are closest wins: on a page of look-alike lines many shifts are passable,
    /// and only the true one lines up the small things that tell the lines apart.
    public static func shift(from previous: [RowSignature], to next: [RowSignature]) -> Int? {
        let count = previous.count
        guard count == next.count, count > 0 else { return nil }
        let largestShift = count - max(1, Int((Double(count) * minimumOverlap).rounded(.up)))
        guard largestShift >= 0 else { return nil }

        var best: (shift: Int, distance: Double)?
        for shift in 0...largestShift {
            let compared = count - shift
            let allowedRows = Int(Double(compared) * tolerance)
            // Past this total the shift cannot beat the best one so far.
            let ceiling = best.map { $0.distance * Double(compared) } ?? .infinity
            var failedRows = 0
            var total = 0.0
            var index = 0
            while index < compared, failedRows <= allowedRows, total <= ceiling {
                let row = previous[index + shift], other = next[index]
                if let distance = row.distance(to: other), let differing = row.differingBands(from: other) {
                    total += distance
                    if differing > row.bands.count / 4 {
                        failedRows += 1
                    }
                } else {
                    failedRows += 1
                }
                index += 1
            }
            guard index == compared, failedRows <= allowedRows else { continue }
            // Per compared row, so a long overlap is not worse off than a short one.
            let distance = total / Double(compared)
            // Strictly better only: of equally good shifts the smallest stands.
            if best == nil || distance < best!.distance {
                best = (shift, distance)
            }
            if total == 0 { break }
        }
        return best?.shift
    }
}
