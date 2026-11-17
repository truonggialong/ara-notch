import SwiftUI

/// The notch's own pictures for what a notice is about: drawn on a 24-point grid with a
/// 1.75-point round stroke, filled only where the picture shows a state (the charge in a
/// battery, the key of Caps Lock, a bell that rings). They replace system symbols in notices,
/// so every notice speaks in the same hand. See docs/research/notice-pictograms.html.
public enum AraPictogram: String, CaseIterable, Sendable {
    case battery, bolt, plug, capsLock, wifi, wifiOff
    case headphones, earbuds, keyboard, mouse
    case speaker, mute, sun, keyLight
    case clipboard, copied, layers, shield, crack
    case note, bell, calendarClock, undo
    case orbit, ask, done, download, update, cup
}

/// One pictogram, drawn at `size` points (24 by default) in the foreground colour.
public struct AraPictogramView: View {
    let pictogram: AraPictogram
    let size: CGFloat

    public init(_ pictogram: AraPictogram, size: CGFloat = 17) {
        self.pictogram = pictogram
        self.size = size
    }

    public var body: some View {
        Canvas { context, area in
            let k = area.width / 24
            context.scaleBy(x: k, y: k)
            AraPictogramDrawing.draw(pictogram, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

enum AraPictogramDrawing {
    static let line: CGFloat = 1.75
    private static let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)

    // MARK: Helpers, all in the 24-point grid

    private static func stroke(_ path: Path, _ c: inout GraphicsContext, width: CGFloat = line, opacity: Double = 1) {
        var c2 = c
        c2.opacity = opacity
        c2.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    private static func fill(_ path: Path, _ c: inout GraphicsContext) {
        c.fill(path, with: .foreground)
    }

    /// Punches the path out of what is drawn, so the colour behind shows through.
    private static func punch(_ path: Path, _ c: inout GraphicsContext, width: CGFloat? = nil) {
        var c2 = c
        c2.blendMode = .destinationOut
        if let width {
            c2.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        } else {
            c2.fill(path, with: .color(.black))
        }
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, r: CGFloat) -> Path {
        Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r, style: .continuous)
    }

    private static func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    private static func lines(_ points: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(points)
        return p
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var p = lines(points)
        p.closeSubpath()
        return p
    }

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// An arc of radius `r` from `a` to `b`, bulging up when `up`, else down; for the waves of
    /// Wi-Fi and of a speaker (`right` bulges to the right).
    private static func arc(_ a: CGPoint, _ b: CGPoint, r: CGFloat, bulge: CGVector) -> Path {
        let mid = pt((a.x + b.x) / 2, (a.y + b.y) / 2)
        let half = hypot(b.x - a.x, b.y - a.y) / 2
        let depth = (r * r - half * half).squareRoot()
        // The centre lies opposite the bulge.
        let centre = pt(mid.x - bulge.dx * depth, mid.y - bulge.dy * depth)
        let start = Angle(radians: atan2(a.y - centre.y, a.x - centre.x))
        let end = Angle(radians: atan2(b.y - centre.y, b.x - centre.x))
        var p = Path()
        // The short way round, through the bulge.
        let mid2 = pt(centre.x + bulge.dx * r, centre.y + bulge.dy * r)
        let midAngle = atan2(mid2.y - centre.y, mid2.x - centre.x)
        let clockwise = !Self.passes(from: start.radians, to: end.radians, through: midAngle, counterClockwiseInView: true)
        p.addArc(center: centre, radius: r, startAngle: start, endAngle: end, clockwise: clockwise)
        return p
    }

    /// Whether going from `a` to `b` with increasing angle (clockwise on screen, y down)
    /// passes `m`.
    private static func passes(from a: Double, to b: Double, through m: Double, counterClockwiseInView: Bool) -> Bool {
        func norm(_ x: Double) -> Double { var y = x.truncatingRemainder(dividingBy: 2 * .pi); if y < 0 { y += 2 * .pi }; return y }
        let span = norm(b - a), at = norm(m - a)
        return at <= span
    }

    private static let speakerBody: [CGPoint] = [pt(4, 9.5), pt(7.5, 9.5), pt(12, 5), pt(12, 19), pt(7.5, 14.5), pt(4, 14.5)]

    private static func clipboardFrame(_ c: inout GraphicsContext, clip: Bool = true) {
        stroke(rect(5, 4.5, 14, 16.5, r: 3), &c)
        if clip { fill(rect(9, 3, 6, 3.5, r: 1.2), &c) }
    }

    private static func wifiWaves(_ c: inout GraphicsContext, opacity: Double) {
        let up = CGVector(dx: 0, dy: -1)
        stroke(arc(pt(3, 9.5), pt(21, 9.5), r: 13, bulge: up), &c, opacity: opacity)
        stroke(arc(pt(6.2, 12.8), pt(17.8, 12.8), r: 8.5, bulge: up), &c, opacity: opacity)
        stroke(arc(pt(9.3, 16), pt(14.7, 16), r: 4, bulge: up), &c, opacity: opacity)
    }

    // MARK: The pictures

    static func draw(_ p: AraPictogram, in c: inout GraphicsContext) {
        switch p {
        case .battery:
            stroke(rect(2.5, 7, 17, 10, r: 3), &c)
            stroke(lines([pt(21.5, 10.5), pt(21.5, 13.5)]), &c)
            fill(rect(4.6, 9.1, 8, 5.8, r: 1.4), &c)
        case .bolt:
            fill(polygon([pt(13, 3), pt(6, 13.5), pt(11, 13.5), pt(10, 21), pt(17, 10.5), pt(12, 10.5)]), &c)
        case .plug:
            stroke(lines([pt(9, 3), pt(9, 7)]), &c)
            stroke(lines([pt(15, 3), pt(15, 7)]), &c)
            var body = Path()
            body.move(to: pt(7, 7))
            body.addLine(to: pt(17, 7))
            body.addLine(to: pt(17, 10))
            body.addArc(center: pt(12, 10), radius: 5, startAngle: .zero, endAngle: .degrees(180), clockwise: false)
            body.closeSubpath()
            stroke(body, &c)
            stroke(lines([pt(12, 15), pt(12, 21)]), &c)
        case .capsLock:
            stroke(rect(3, 3, 18, 18, r: 5), &c)
            fill(polygon([pt(12, 7), pt(7.5, 12), pt(10, 12), pt(10, 15.5), pt(14, 15.5), pt(14, 12), pt(16.5, 12)]), &c)
            stroke(lines([pt(10, 17.5), pt(14, 17.5)]), &c)
        case .wifi:
            wifiWaves(&c, opacity: 1)
            fill(circle(12, 19, 1.4), &c)
        case .wifiOff:
            wifiWaves(&c, opacity: 0.35)
            stroke(lines([pt(4, 4), pt(20, 20)]), &c)
        case .headphones:
            var band = Path()
            band.move(to: pt(4, 15))
            band.addLine(to: pt(4, 12))
            band.addArc(center: pt(12, 12), radius: 8, startAngle: .degrees(180), endAngle: .zero, clockwise: false)
            band.addLine(to: pt(20, 15))
            stroke(band, &c)
            fill(rect(3, 14, 5, 7, r: 2), &c)
            fill(rect(16, 14, 5, 7, r: 2), &c)
        case .earbuds:
            stroke(rect(4, 4, 7, 9, r: 3.5), &c)
            stroke(rect(13, 4, 7, 9, r: 3.5), &c)
            stroke(lines([pt(5.5, 12.5), pt(5.5, 20)]), &c)
            stroke(lines([pt(18.5, 12.5), pt(18.5, 20)]), &c)
        case .keyboard:
            stroke(rect(2.5, 6, 19, 12, r: 3), &c)
            for x in [6.0, 9.5, 13, 16.5] { fill(circle(x, 10, 1), &c) }
            stroke(lines([pt(8, 14), pt(16, 14)]), &c)
        case .mouse:
            stroke(rect(6, 3, 12, 18, r: 6), &c)
            stroke(lines([pt(12, 7), pt(12, 10)]), &c)
        case .speaker:
            fill(polygon(speakerBody), &c)
            let right = CGVector(dx: 1, dy: 0)
            stroke(arc(pt(15.5, 9), pt(15.5, 15), r: 4, bulge: right), &c)
            stroke(arc(pt(18, 6.5), pt(18, 17.5), r: 7.5, bulge: right), &c)
        case .mute:
            fill(polygon(speakerBody), &c)
            stroke(lines([pt(16, 9.5), pt(21, 14.5)]), &c)
            stroke(lines([pt(21, 9.5), pt(16, 14.5)]), &c)
        case .sun:
            fill(circle(12, 12, 4), &c)
            let rays: [(CGPoint, CGPoint)] = [
                (pt(12, 2.5), pt(12, 4.5)), (pt(12, 19.5), pt(12, 21.5)), (pt(2.5, 12), pt(4.5, 12)), (pt(19.5, 12), pt(21.5, 12)),
                (pt(5.3, 5.3), pt(6.7, 6.7)), (pt(17.3, 17.3), pt(18.7, 18.7)), (pt(5.3, 18.7), pt(6.7, 17.3)), (pt(17.3, 6.7), pt(18.7, 5.3)),
            ]
            for (a, b) in rays { stroke(lines([a, b]), &c) }
        case .keyLight:
            stroke(rect(3, 11, 18, 9, r: 2.5), &c)
            stroke(lines([pt(12, 3), pt(12, 6)]), &c)
            stroke(lines([pt(6.5, 5), pt(8, 7)]), &c)
            stroke(lines([pt(17.5, 5), pt(16, 7)]), &c)
            stroke(lines([pt(7, 15.5), pt(17, 15.5)]), &c)
        case .clipboard:
            clipboardFrame(&c)
            stroke(lines([pt(9, 11), pt(15, 11)]), &c)
            stroke(lines([pt(9, 14.5), pt(13, 14.5)]), &c)
        case .copied:
            clipboardFrame(&c)
            stroke(lines([pt(8.8, 13.2), pt(11, 15.4), pt(15.2, 10.8)]), &c, width: 1.9)
        case .layers:
            fill(polygon([pt(12, 3), pt(3, 8), pt(12, 13), pt(21, 8)]), &c)
            stroke(lines([pt(3, 12.5), pt(12, 17.5), pt(21, 12.5)]), &c)
            stroke(lines([pt(3, 16.5), pt(12, 21.5), pt(21, 16.5)]), &c)
        case .shield:
            var s = Path()
            s.move(to: pt(12, 3))
            s.addLine(to: pt(4.5, 6))
            s.addLine(to: pt(4.5, 11.5))
            s.addQuadCurve(to: pt(12, 21), control: pt(5, 18))
            s.addQuadCurve(to: pt(19.5, 11.5), control: pt(19, 18))
            s.addLine(to: pt(19.5, 6))
            s.closeSubpath()
            stroke(s, &c)
            fill(rect(9.5, 10, 5, 4.5, r: 1), &c)
            stroke(lines([pt(8.5, 15.5), pt(15.5, 8.5)]), &c)
        case .crack:
            clipboardFrame(&c, clip: false)
            stroke(lines([pt(12, 7), pt(10, 11), pt(13, 11), pt(11, 16)]), &c)
        case .note:
            stroke(lines([pt(9, 17.5), pt(9, 6), pt(19, 4), pt(19, 15.5)]), &c)
            fill(circle(6.5, 17.5, 2.7), &c)
            fill(circle(16.5, 15.5, 2.7), &c)
        case .bell:
            var b = Path()
            b.move(to: pt(6, 16))
            b.addLine(to: pt(6, 11))
            b.addArc(center: pt(12, 11), radius: 6, startAngle: .degrees(180), endAngle: .zero, clockwise: false)
            b.addLine(to: pt(18, 16))
            b.addLine(to: pt(19.5, 18))
            b.addLine(to: pt(4.5, 18))
            b.closeSubpath()
            fill(b, &c)
            var clapper = Path()
            clapper.addArc(center: pt(12, 20.5), radius: 2, startAngle: .degrees(180), endAngle: .zero, clockwise: true)
            stroke(clapper, &c)
        case .calendarClock:
            stroke(rect(3, 5, 13, 13, r: 3), &c)
            stroke(lines([pt(7, 3), pt(7, 6)]), &c)
            stroke(lines([pt(12, 3), pt(12, 6)]), &c)
            stroke(lines([pt(3, 9), pt(16, 9)]), &c)
            punch(circle(17, 16.5, 5.8), &c)
            fill(circle(17, 16.5, 4.5), &c)
            punch(lines([pt(17, 14.5), pt(17, 16.7), pt(18.4, 17.7)]), &c, width: 1.4)
        case .undo:
            stroke(circle(12, 12, 8.5), &c)
            stroke(lines([pt(8, 12.2), pt(10.6, 14.8), pt(16, 9.2)]), &c, width: 1.9)
        case .orbit:
            fill(circle(12, 12, 3), &c)
            var c2 = c
            c2.stroke(circle(12, 12, 8), with: .foreground, style: StrokeStyle(lineWidth: line, lineCap: .round, dash: [12, 6]))
        case .ask:
            stroke(rect(4, 3, 16, 13, r: 3.5), &c)
            punch(lines([pt(7.5, 16), pt(10.5, 16)]), &c, width: 2.2)
            stroke(lines([pt(11, 16), pt(6.5, 20), pt(6.5, 16)]), &c)
            for x in [8.5, 12, 15.5] { fill(circle(x, 9.5, 1.2), &c) }
        case .done:
            fill(circle(12, 12, 9), &c)
            punch(lines([pt(8, 12.3), pt(10.7, 15), pt(16.2, 9.5)]), &c, width: 2)
        case .download:
            stroke(lines([pt(12, 3.5), pt(12, 13.5)]), &c)
            stroke(lines([pt(8, 9.5), pt(12, 13.5), pt(16, 9.5)]), &c)
            var tray = Path()
            tray.move(to: pt(4, 14))
            tray.addLine(to: pt(4, 17.5))
            tray.addQuadCurve(to: pt(6.5, 20), control: pt(4, 20))
            tray.addLine(to: pt(17.5, 20))
            tray.addQuadCurve(to: pt(20, 17.5), control: pt(20, 20))
            tray.addLine(to: pt(20, 14))
            stroke(tray, &c)
        case .update:
            stroke(circle(12, 12, 8.5), &c)
            stroke(lines([pt(12, 16.5), pt(12, 8)]), &c)
            stroke(lines([pt(8.5, 11.5), pt(12, 8), pt(15.5, 11.5)]), &c)
            punch(circle(19, 5, 3.4), &c)
            fill(circle(19, 5, 2.2), &c)
        case .cup:
            var cup = Path()
            cup.move(to: pt(4, 9))
            cup.addLine(to: pt(16, 9))
            cup.addLine(to: pt(16, 14))
            cup.addQuadCurve(to: pt(11, 19), control: pt(16, 19))
            cup.addLine(to: pt(9, 19))
            cup.addQuadCurve(to: pt(4, 14), control: pt(4, 19))
            cup.closeSubpath()
            fill(cup, &c)
            var handle = Path()
            handle.move(to: pt(16, 10.5))
            handle.addLine(to: pt(17.5, 10.5))
            handle.addArc(center: pt(17.5, 13), radius: 2.5, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            handle.addLine(to: pt(16, 15.5))
            stroke(handle, &c)
            stroke(lines([pt(8, 3.5), pt(9, 6.2)]), &c)
            stroke(lines([pt(12, 3.5), pt(13, 6.2)]), &c)
        }
    }
}
