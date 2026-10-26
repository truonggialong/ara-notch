import AppKit
import SwiftUI

/// The app's own drawings, for the places that give it a face: the tabs of the notch and the
/// menu bar. Each is drawn on a 24-point square with round-ended strokes of one weight, and a
/// few solid parts.
public enum AraGlyph: String, CaseIterable, Sendable {
    case clipboard, music, timer, calendar, files, agents, about, settings
    /// The app's mark: a screen with its notch.
    case mark

    /// The drawing for a page of the notch, by the page's id.
    public init?(pageID: String) {
        switch pageID {
        case "clipboard": self = .clipboard
        case "media": self = .music
        case "timer": self = .timer
        case "calendar": self = .calendar
        case "files": self = .files
        case "agents": self = .agents
        case "about": self = .about
        default: return nil
        }
    }

    /// The parts drawn as lines, on the 24-point square.
    var strokes: Path {
        var path = Path()
        switch self {
        case .clipboard:
            // A board whose top edge is broken by the clip.
            path.move(to: CGPoint(x: 9, y: 5))
            path.addLine(to: CGPoint(x: 8, y: 5))
            path.addQuadCurve(to: CGPoint(x: 5.5, y: 7.5), control: CGPoint(x: 5.5, y: 5))
            path.addLine(to: CGPoint(x: 5.5, y: 18))
            path.addQuadCurve(to: CGPoint(x: 8, y: 20.5), control: CGPoint(x: 5.5, y: 20.5))
            path.addLine(to: CGPoint(x: 16, y: 20.5))
            path.addQuadCurve(to: CGPoint(x: 18.5, y: 18), control: CGPoint(x: 18.5, y: 20.5))
            path.addLine(to: CGPoint(x: 18.5, y: 7.5))
            path.addQuadCurve(to: CGPoint(x: 16, y: 5), control: CGPoint(x: 18.5, y: 5))
            path.addLine(to: CGPoint(x: 15, y: 5))
            path.addRoundedRect(in: CGRect(x: 9, y: 3.2, width: 6, height: 3.6), cornerSize: CGSize(width: 1.6, height: 1.6))
            path.move(to: CGPoint(x: 9, y: 11.5))
            path.addLine(to: CGPoint(x: 15, y: 11.5))
            path.move(to: CGPoint(x: 9, y: 15.5))
            path.addLine(to: CGPoint(x: 13, y: 15.5))
        case .music:
            // Two stems joined by a beam.
            path.move(to: CGPoint(x: 9.6, y: 17))
            path.addLine(to: CGPoint(x: 9.6, y: 6.6))
            path.addLine(to: CGPoint(x: 18.4, y: 4.6))
            path.addLine(to: CGPoint(x: 18.4, y: 15))
        case .timer:
            path.addEllipse(in: CGRect(x: 4.8, y: 6.4, width: 14.4, height: 14.4))
            path.move(to: CGPoint(x: 10, y: 3.4))
            path.addLine(to: CGPoint(x: 14, y: 3.4))
            path.move(to: CGPoint(x: 12, y: 3.4))
            path.addLine(to: CGPoint(x: 12, y: 6.2))
            path.move(to: CGPoint(x: 12, y: 13.6))
            path.addLine(to: CGPoint(x: 15, y: 10.6))
        case .calendar:
            path.addRoundedRect(in: CGRect(x: 4.5, y: 5.5, width: 15, height: 15), cornerSize: CGSize(width: 3.4, height: 3.4))
            path.move(to: CGPoint(x: 4.5, y: 10))
            path.addLine(to: CGPoint(x: 19.5, y: 10))
            path.move(to: CGPoint(x: 8.6, y: 3.6))
            path.addLine(to: CGPoint(x: 8.6, y: 6.6))
            path.move(to: CGPoint(x: 15.4, y: 3.6))
            path.addLine(to: CGPoint(x: 15.4, y: 6.6))
        case .files:
            // A tray, and an arrow coming down into it.
            path.move(to: CGPoint(x: 4.5, y: 13.5))
            path.addLine(to: CGPoint(x: 4.5, y: 17.5))
            path.addQuadCurve(to: CGPoint(x: 7, y: 20), control: CGPoint(x: 4.5, y: 20))
            path.addLine(to: CGPoint(x: 17, y: 20))
            path.addQuadCurve(to: CGPoint(x: 19.5, y: 17.5), control: CGPoint(x: 19.5, y: 20))
            path.addLine(to: CGPoint(x: 19.5, y: 13.5))
            path.move(to: CGPoint(x: 4.5, y: 13.5))
            path.addLine(to: CGPoint(x: 8.4, y: 13.5))
            path.addQuadCurve(to: CGPoint(x: 10, y: 15.6), control: CGPoint(x: 9, y: 15.6))
            path.addLine(to: CGPoint(x: 14, y: 15.6))
            path.addQuadCurve(to: CGPoint(x: 15.6, y: 13.5), control: CGPoint(x: 15, y: 15.6))
            path.addLine(to: CGPoint(x: 19.5, y: 13.5))
            path.move(to: CGPoint(x: 12, y: 3.6))
            path.addLine(to: CGPoint(x: 12, y: 10.6))
            path.move(to: CGPoint(x: 9.2, y: 8))
            path.addLine(to: CGPoint(x: 12, y: 10.8))
            path.addLine(to: CGPoint(x: 14.8, y: 8))
        case .agents:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 5, width: 17, height: 14.5), cornerSize: CGSize(width: 3.4, height: 3.4))
            path.move(to: CGPoint(x: 7.6, y: 9.6))
            path.addLine(to: CGPoint(x: 10.6, y: 12.2))
            path.addLine(to: CGPoint(x: 7.6, y: 14.8))
            path.move(to: CGPoint(x: 12.6, y: 15))
            path.addLine(to: CGPoint(x: 16.4, y: 15))
        case .about:
            path.addEllipse(in: CGRect(x: 3.8, y: 3.8, width: 16.4, height: 16.4))
            path.move(to: CGPoint(x: 12, y: 11.4))
            path.addLine(to: CGPoint(x: 12, y: 16.2))
        case .settings:
            // Three sliders.
            for y in [7.0, 12.0, 17.0] {
                path.move(to: CGPoint(x: 4.5, y: y))
                path.addLine(to: CGPoint(x: 19.5, y: y))
            }
        case .mark:
            path.addRoundedRect(in: CGRect(x: 3.5, y: 5.5, width: 17, height: 13.5), cornerSize: CGSize(width: 3.6, height: 3.6))
        }
        return path
    }

    /// The solid parts.
    var solids: Path {
        var path = Path()
        switch self {
        case .music:
            path.addEllipse(in: CGRect(x: 5.2, y: 15, width: 5.2, height: 4.2))
            path.addEllipse(in: CGRect(x: 14, y: 13, width: 5.2, height: 4.2))
        case .calendar:
            for point in [CGPoint(x: 8.6, y: 13.6), CGPoint(x: 12, y: 13.6), CGPoint(x: 15.4, y: 13.6), CGPoint(x: 8.6, y: 17)] {
                path.addEllipse(in: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2))
            }
        case .about:
            path.addEllipse(in: CGRect(x: 10.8, y: 6.9, width: 2.4, height: 2.4))
        case .settings:
            for point in [CGPoint(x: 15, y: 7), CGPoint(x: 9, y: 12), CGPoint(x: 13.5, y: 17)] {
                path.addEllipse(in: CGRect(x: point.x - 2.3, y: point.y - 2.3, width: 4.6, height: 4.6))
            }
        case .mark:
            // The notch, hanging from the top edge of the screen.
            path.move(to: CGPoint(x: 8.2, y: 5.5))
            path.addLine(to: CGPoint(x: 15.8, y: 5.5))
            path.addLine(to: CGPoint(x: 15.8, y: 7.4))
            path.addQuadCurve(to: CGPoint(x: 14, y: 9.2), control: CGPoint(x: 15.8, y: 9.2))
            path.addLine(to: CGPoint(x: 10, y: 9.2))
            path.addQuadCurve(to: CGPoint(x: 8.2, y: 7.4), control: CGPoint(x: 8.2, y: 9.2))
            path.closeSubpath()
        default:
            break
        }
        return path
    }

    /// The glyph as a template image, for the menu bar.
    @MainActor
    public func image(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let scale = size / 24
            context.scaleBy(x: scale, y: scale)
            context.setLineWidth(1.9)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(self.strokes.cgPath)
            context.strokePath()
            context.addPath(self.solids.cgPath)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Draws a glyph in the current foreground style.
public struct AraGlyphView: View {
    @Environment(\.araScale) private var ui
    let glyph: AraGlyph
    var size: CGFloat

    public init(_ glyph: AraGlyph, size: CGFloat = 16) {
        self.glyph = glyph
        self.size = size
    }

    public var body: some View {
        let side = size * ui
        let scale = side / 24
        ZStack {
            glyph.strokes
                .applying(CGAffineTransform(scaleX: scale, y: scale))
                .stroke(style: StrokeStyle(lineWidth: 1.9 * scale, lineCap: .round, lineJoin: .round))
            glyph.solids
                .applying(CGAffineTransform(scaleX: scale, y: scale))
                .fill()
        }
        .frame(width: side, height: side)
    }
}
