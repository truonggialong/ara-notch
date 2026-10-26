import CoreGraphics
import Foundation

/// A colour for drawing on a capture.
public struct AnnotationColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let red = AnnotationColor(red: 1, green: 0.23, blue: 0.19)
    public static let yellow = AnnotationColor(red: 1, green: 0.8, blue: 0)
    public static let green = AnnotationColor(red: 0.2, green: 0.78, blue: 0.35)
    public static let blue = AnnotationColor(red: 0.04, green: 0.52, blue: 1)
    public static let white = AnnotationColor(red: 1, green: 1, blue: 1)
    public static let black = AnnotationColor(red: 0, green: 0, blue: 0)

    public static let palette: [AnnotationColor] = [.red, .yellow, .green, .blue, .white, .black]
}

/// What the pointer draws on a capture.
public enum AnnotationTool: String, CaseIterable, Sendable {
    case arrow
    case line
    case rectangle
    case ellipse
    case highlight
    case pen
    case text
    /// A numbered mark: 1, 2, 3 in the order they are placed.
    case step
    /// Hides what is under it behind coarse blocks.
    case blur
}

/// How thick the pointer draws, in points on screen.
public enum AnnotationStroke: String, CaseIterable, Sendable {
    case small, medium, large

    public var width: CGFloat {
        switch self {
        case .small: 2.5
        case .medium: 4
        case .large: 7
        }
    }
}

/// How a box is broken into blocks to hide what is under it.
public enum MosaicGeometry {
    public struct Blocks: Equatable, Sendable {
        public let columns: Int
        public let rows: Int
    }

    /// The side of one block, in the picture's points.
    static let blockSide: CGFloat = 12

    public static func blocks(for size: CGSize) -> Blocks {
        // Rounded up, so a part block at the edge is a block of its own.
        Blocks(
            columns: max(Int((size.width / blockSide).rounded(.up)), 1),
            rows: max(Int((size.height / blockSide).rounded(.up)), 1))
    }
}

/// One thing drawn on a capture. Coordinates are in the image's own points, origin top left.
public struct Annotation: Equatable, Identifiable, Sendable {
    public enum Shape: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rectangle(CGRect)
        case ellipse(CGRect)
        /// A numbered mark, centred on the point.
        case step(Int, at: CGPoint)
        /// A box whose content is hidden behind coarse blocks.
        case blur(CGRect)
        /// A see-through filled box, like a marker pen.
        case highlight(CGRect)
        case pen([CGPoint])
        case text(String, at: CGPoint)
    }

    public let id: Int
    public var shape: Shape
    public var color: AnnotationColor
    public var lineWidth: CGFloat
}

/// The annotations on a capture, with undo and redo.
public struct AnnotationDocument: Equatable, Sendable {
    /// A drag shorter than this draws nothing.
    static let minimumDrag: CGFloat = 4

    public private(set) var annotations: [Annotation] = []
    private var undone: [Annotation] = []
    private var nextID = 1

    public init() {}

    /// The number the next step mark gets: one more than the marks on the picture now.
    public var nextStepNumber: Int {
        annotations.filter { if case .step = $0.shape { true } else { false } }.count + 1
    }

    public var canUndo: Bool { !annotations.isEmpty }
    public var canRedo: Bool { !undone.isEmpty }

    public mutating func add(_ shape: Annotation.Shape, color: AnnotationColor, lineWidth: CGFloat) {
        annotations.append(Annotation(id: nextID, shape: shape, color: color, lineWidth: lineWidth))
        nextID += 1
        undone = []
    }

    /// Changes the shape added last, while it is still being dragged out.
    public mutating func replaceLast(with shape: Annotation.Shape) {
        guard !annotations.isEmpty else { return }
        annotations[annotations.count - 1].shape = shape
    }

    public mutating func undo() {
        guard let last = annotations.popLast() else { return }
        undone.append(last)
    }

    public mutating func redo() {
        guard let last = undone.popLast() else { return }
        annotations.append(last)
    }

    /// The shape a drag with this tool makes, or nil when the drag is too small to mean anything.
    /// - Parameters:
    ///   - path: every point the pointer went through, for the pen.
    ///   - text: what the text tool writes.
    ///   - step: the number the step tool marks.
    public static func shape(
        for tool: AnnotationTool, from: CGPoint, to: CGPoint, path: [CGPoint], text: String, step: Int = 1
    ) -> Annotation.Shape? {
        let isDrag = hypot(to.x - from.x, to.y - from.y) >= minimumDrag
        let box = CGRect(
            x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
        switch tool {
        case .arrow:
            return isDrag ? .arrow(from: from, to: to) : nil
        case .line:
            return isDrag ? .line(from: from, to: to) : nil
        case .rectangle:
            return isDrag ? .rectangle(box) : nil
        case .ellipse:
            return isDrag ? .ellipse(box) : nil
        case .blur:
            return isDrag ? .blur(box) : nil
        case .step:
            // Placed with a click; a drag moves it along until the button comes up.
            return .step(step, at: to)
        case .highlight:
            return isDrag ? .highlight(box) : nil
        case .pen:
            return path.count >= 2 && isDrag ? .pen(path) : nil
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed, at: to)
        }
    }
}

/// The two barbs of an arrow's head.
public enum ArrowGeometry {
    /// Half the angle the head opens to.
    static let spread: CGFloat = .pi / 6

    /// The ends of the two barbs, which start at the tip and point back along the shaft.
    public static func head(from: CGPoint, to: CGPoint, length: CGFloat) -> (CGPoint, CGPoint) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        func barb(_ offset: CGFloat) -> CGPoint {
            CGPoint(x: to.x - length * cos(angle + offset), y: to.y - length * sin(angle + offset))
        }
        return (barb(spread), barb(-spread))
    }
}

/// Puts pieces of recognised text back into reading order.
public enum RecognizedLines {
    /// A piece of text and where it was found: 0…1 of the image, origin at the bottom left.
    public struct Line: Equatable, Sendable {
        public var text: String
        public var box: CGRect

        public init(text: String, box: CGRect) {
            self.text = text
            self.box = box
        }
    }

    /// Top to bottom; pieces on the same row are joined left to right with a space.
    public static func text(_ lines: [Line]) -> String {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.box.midY > $1.box.midY }) {
            // On the same row when the centre lies within half the height of the row's first piece.
            if let first = rows.last?.first, abs(first.box.midY - line.box.midY) < first.box.height / 2 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}

/// Names the file a capture is saved to.
public enum CaptureNaming {
    public static func fileName(at date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "AraNotch %04d-%02d-%02d %02d.%02d.%02d.png",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
}

/// Reads and writes the screen capture settings.
public struct CaptureSettingsStore {
    public enum Key {
        public static let shortcutEnabled = "capture.shortcutEnabled"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Capture a region with the global shortcut.
    public var shortcutEnabled: Bool {
        get { defaults.object(forKey: Key.shortcutEnabled) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.shortcutEnabled) }
    }
}

/// A colour picked from the screen, as text.
public enum ScreenColor {
    /// "#RRGGBB" from components 0…1; values a little outside that range are clamped.
    public static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}

