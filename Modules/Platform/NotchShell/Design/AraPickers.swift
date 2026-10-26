import NotchCore
import SwiftUI

/// Names typed before, for features that do not see the core module.

/// A day and a time of day put together and taken apart, in the user's calendar.
public enum AraMoment {
    public static func moment(on day: Date, minutesOfDay: Int) -> Date {
        MonthGrid.moment(on: day, minutesOfDay: minutesOfDay, calendar: .current)
    }

    public static func minutesOfDay(of date: Date) -> Int {
        MonthGrid.minutesOfDay(of: date, calendar: .current)
    }
}

/// Which hand of the clock face is being set.
@MainActor
final class AraClockStep: ObservableObject {
    @Published var isChoosingMinutes = false
}

/// A time of day chosen on a clock face, in two steps: the hour, then the face turns to the
/// minutes. Nothing is typed.
public struct AraClockFace: View {
    @Environment(\.araScale) private var ui
    @Binding var minutesOfDay: Int
    var diameter: CGFloat
    @StateObject private var step = AraClockStep()
    @Environment(\.araHue) private var hue

    public init(minutesOfDay: Binding<Int>, diameter: CGFloat = 118) {
        _minutesOfDay = minutesOfDay
        self.diameter = diameter
    }

    private var hour: Int { minutesOfDay / 60 }
    private var minute: Int { minutesOfDay % 60 }

    public var body: some View {
        VStack(spacing: 4 * ui) {
            heading
            AraDialFace(diameter: diameter, hands: hands, labels: labels) { angle, isInner, isLast in
                if step.isChoosingMinutes {
                    minutesOfDay = ClockDial.minutesOfDay(hour: hour, minute: ClockDial.minute(angle: angle))
                } else {
                    minutesOfDay = ClockDial.minutesOfDay(hour: ClockDial.hour(angle: angle, isInner: isInner), minute: minute)
                    // The hour is set when the pointer lets go: on to the minutes.
                    if isLast {
                        step.isChoosingMinutes = true
                    }
                }
            }
        }
    }

    /// "14 : 30", each part a button back to its step.
    private var heading: some View {
        HStack(spacing: 2 * ui) {
            part(String(format: "%02d", hour), isActive: !step.isChoosingMinutes, help: "picker.hour") {
                step.isChoosingMinutes = false
            }
            Text(":")
                .font(.system(size: 15 * ui, weight: .semibold, design: .rounded))
                .opacity(0.6)
            part(String(format: "%02d", minute), isActive: step.isChoosingMinutes, help: "picker.minute") {
                step.isChoosingMinutes = true
            }
        }
    }

    private func part(_ text: String, isActive: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15 * ui, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isActive ? AraPalette.onAccent(in: hue) : AraPalette.ink)
                .frame(width: 32 * ui, height: 22 * ui)
                .background(isActive ? AraPalette.accent(in: hue) : AraPalette.well, in: RoundedRectangle(cornerRadius: 7 * ui, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle())
        .accessibilityLabel(L10n.string(help))
    }

    private var hands: [AraDialFace.Hand] {
        if step.isChoosingMinutes {
            return [.init(angle: ClockDial.angle(ofMinute: minute), share: AraDialFace.outerShare, text: minute % 5 == 0 ? nil : "")]
        }
        let place = ClockDial.place(ofHour: hour)
        return [.init(angle: place.angle, share: place.isInner ? AraDialFace.innerShare : AraDialFace.outerShare, text: nil)]
    }

    private var labels: [AraDialFace.Label] {
        if step.isChoosingMinutes {
            return (0..<12).map { index in
                .init(text: String(format: "%02d", index * 5), angle: Double(index) * 30, share: AraDialFace.outerShare,
                      isSelected: minute == index * 5, isQuiet: false)
            }
        }
        let outer = ClockDial.outerHours.enumerated().map { index, value in
            AraDialFace.Label(
                text: String(value), angle: Double(index) * 30, share: AraDialFace.outerShare, isSelected: hour == value,
                isQuiet: false)
        }
        let inner = ClockDial.innerHours.enumerated().map { index, value in
            AraDialFace.Label(
                text: String(format: "%02d", value), angle: Double(index) * 30, share: AraDialFace.innerShare,
                isSelected: hour == value, isQuiet: true)
        }
        return outer + inner
    }
}

/// A length of time chosen on a face: the minutes round the outside, the hours (none to
/// three) inside. Seconds are stepped with two small buttons.
public struct AraLengthDial: View {
    @Environment(\.araScale) private var ui
    /// The whole length in seconds.
    @Binding var seconds: Int
    var diameter: CGFloat
    @Environment(\.araHue) private var hue

    public init(seconds: Binding<Int>, diameter: CGFloat = 132) {
        _seconds = seconds
        self.diameter = diameter
    }

    private var hours: Int { seconds / 3_600 }
    private var minutes: Int { (seconds % 3_600) / 60 }
    private var rest: Int { seconds % 60 }

    public var body: some View {
        AraDialFace(diameter: diameter, hands: hands, labels: labels, keepsToRing: true) { angle, isInner, _ in
            if isInner {
                seconds = ClockDial.lengthHour(angle: angle) * 3_600 + minutes * 60 + rest
            } else {
                seconds = hours * 3_600 + ClockDial.minute(angle: angle) * 60 + rest
            }
        }
    }

    private var hands: [AraDialFace.Hand] {
        [
            .init(angle: ClockDial.angle(ofMinute: minutes), share: AraDialFace.outerShare, text: minutes % 5 == 0 ? nil : ""),
            .init(angle: ClockDial.angle(ofLengthHour: hours), share: AraDialFace.innerShare, text: nil),
        ]
    }

    private var labels: [AraDialFace.Label] {
        let outer = (0..<12).map { index in
            AraDialFace.Label(
                text: String(index * 5), angle: Double(index) * 30, share: AraDialFace.outerShare,
                isSelected: minutes == index * 5, isQuiet: false)
        }
        let inner = (0..<4).map { index in
            AraDialFace.Label(
                text: String(format: L10n.string("picker.hours.short"), index), angle: Double(index) * 90,
                share: AraDialFace.innerShare, isSelected: hours == index, isQuiet: true)
        }
        return outer + inner
    }
}

/// Which ring a drag on a dial began on.
@MainActor
final class AraDialDrag: ObservableObject {
    var ring: Bool?
}

/// The round face both dials are drawn on: numbers on one or two rings, a hand to each
/// chosen number, and one gesture that reports where the pointer is as an angle and a ring.
struct AraDialFace: View {
    @Environment(\.araScale) private var ui
    struct Hand {
        let angle: Double
        /// How far out the hand reaches, as a share of the radius.
        let share: Double
        /// What the knob says when it sits between two numbers; nil when a number is under it.
        let text: String?
    }

    struct Label: Identifiable {
        let text: String
        let angle: Double
        let share: Double
        let isSelected: Bool
        let isQuiet: Bool
        var id: String { "\(share)-\(angle)" }
    }

    static let outerShare = 0.82
    static let innerShare = 0.5

    let diameter: CGFloat
    let hands: [Hand]
    let labels: [Label]
    /// True when the two rings are two different things: a drag then stays with the ring
    /// it began on, however near the centre it passes.
    var keepsToRing = false
    @StateObject private var drag = AraDialDrag()
    /// The pointer is at this angle, on the inner ring or not; `isLast` when it lets go.
    let onPoint: (_ angle: Double, _ isInner: Bool, _ isLast: Bool) -> Void
    @Environment(\.araHue) private var hue

    var body: some View {
        let side = diameter * ui
        let radius = side / 2
        ZStack {
            Circle().fill(AraPalette.well)
            ForEach(Array(hands.enumerated()), id: \.offset) { _, hand in
                let end = point(angle: hand.angle, share: hand.share, radius: radius)
                Path { path in
                    path.move(to: CGPoint(x: radius, y: radius))
                    path.addLine(to: end)
                }
                .stroke(AraPalette.accent(in: hue), lineWidth: 1.5 * ui)
                Circle()
                    .fill(AraPalette.accent(in: hue))
                    .frame(width: knob(hand.share), height: knob(hand.share))
                    .position(end)
            }
            Circle()
                .fill(AraPalette.accent(in: hue))
                .frame(width: 5 * ui, height: 5 * ui)
            ForEach(labels) { label in
                Text(label.text)
                    .font(.system(size: (label.isQuiet ? 9 : 10.5) * ui, weight: label.isSelected ? .bold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(
                        label.isSelected ? AraPalette.onAccent(in: hue) : AraPalette.ink.opacity(label.isQuiet ? 0.62 : 0.92))
                    .position(point(angle: label.angle, share: label.share, radius: radius))
            }
        }
        .frame(width: side, height: side)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in report(value.location, radius: radius, isLast: false) }
                .onEnded { value in
                    report(value.location, radius: radius, isLast: true)
                    AraHaptics.play(.tap)
                })
    }

    private func knob(_ share: Double) -> CGFloat {
        (share < 0.7 ? 19 : 22) * ui
    }

    private func point(angle: Double, share: Double, radius: CGFloat) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(
            x: radius + radius * share * sin(radians),
            y: radius - radius * share * cos(radians))
    }

    private func report(_ location: CGPoint, radius: CGFloat, isLast: Bool) {
        let dx = location.x - radius, dy = location.y - radius
        let distance = (dx * dx + dy * dy).squareRoot()
        // The very centre says nothing about a direction.
        guard distance > 6 * ui || drag.ring != nil else { return }
        let isInner = (keepsToRing ? drag.ring : nil) ?? ClockDial.isInner(distance: distance, radius: radius)
        drag.ring = isLast ? nil : isInner
        onPoint(ClockDial.angle(dx: dx, dy: dy), isInner, isLast)
    }
}

/// The month a calendar is showing, when it is not the month of the chosen day.
@MainActor
final class AraShownMonth: ObservableObject {
    @Published var month: Date?
}

/// A day chosen from a month laid out as a calendar, with arrows to the months around it.
public struct AraMonthCalendar: View {
    @Environment(\.araScale) private var ui
    @Binding var day: Date
    var today: Date
    var marked: Set<Date>
    var onShowMonth: ((Date) -> Void)?
    var onPick: (() -> Void)?
    @StateObject private var shown = AraShownMonth()
    @Environment(\.araHue) private var hue

    /// - Parameters:
    ///   - marked: days to put a dot under, each at its start: those with something on them.
    ///   - onShowMonth: called with the first day of a month when the calendar turns to it.
    ///   - onPick: called after a day was clicked, for a calendar that closes then.
    public init(
        day: Binding<Date>, today: Date = Date(), marked: Set<Date> = [], onShowMonth: ((Date) -> Void)? = nil,
        onPick: (() -> Void)? = nil
    ) {
        _day = day
        self.today = today
        self.marked = marked
        self.onShowMonth = onShowMonth
        self.onPick = onPick
    }

    private func show(_ month: Date) {
        shown.month = month
        onShowMonth?(month)
    }

    private static let cell = CGSize(width: 25, height: 17)

    public var body: some View {
        let calendar = Calendar.current
        let grid = MonthGrid(containing: shown.month ?? day, calendar: calendar)
        VStack(spacing: 2 * ui) {
            HStack(spacing: 4 * ui) {
                AraIconButton(.back, look: .bare, size: .small, help: L10n.string("picker.month.previous")) {
                    show(MonthGrid.shifting(grid.month, months: -1, calendar: calendar))
                }
                Text(Self.title.string(from: grid.month))
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .frame(maxWidth: .infinity)
                AraIconButton(.forward, look: .bare, size: .small, help: L10n.string("picker.month.next")) {
                    show(MonthGrid.shifting(grid.month, months: 1, calendar: calendar))
                }
            }
            .frame(height: 20 * ui)
            HStack(spacing: 0 * ui) {
                ForEach(Array(Self.weekdays(calendar).enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 8.5 * ui, weight: .semibold))
                        .foregroundStyle(AraPalette.label(in: hue))
                        .frame(width: Self.cell.width * ui, height: 12 * ui)
                }
            }
            ForEach(Array(grid.weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0 * ui) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        if let date {
                            AraDayCell(
                                number: calendar.component(.day, from: date),
                                isSelected: calendar.isDate(date, inSameDayAs: day),
                                isToday: calendar.isDate(date, inSameDayAs: today),
                                isMarked: marked.contains(calendar.startOfDay(for: date))
                            ) {
                                // A day of another month than the one first shown: the calendar stays on it.
                                shown.month = grid.month
                                day = calendar.startOfDay(for: date)
                                onPick?()
                            }
                            .frame(width: Self.cell.width * ui, height: Self.cell.height * ui)
                        } else {
                            Color.clear.frame(width: Self.cell.width * ui, height: Self.cell.height * ui)
                        }
                    }
                }
            }
            Spacer(minLength: 0 * ui)
        }
        .frame(width: Self.cell.width * ui * 7)
        // A day set from outside, by a button beside the calendar, in a month other than
        // the one turned to: the calendar goes to it.
        .onChange(of: day) { _, chosen in
            guard let month = shown.month, !calendar.isDate(chosen, equalTo: month, toGranularity: .month) else { return }
            show(MonthGrid(containing: chosen, calendar: calendar).month)
        }
    }

    /// The short names of the weekdays, from the calendar's first.
    private static func weekdays(_ calendar: Calendar) -> [String] {
        let names = title.veryShortStandaloneWeekdaySymbols ?? []
        guard names.count == 7 else { return names }
        let first = calendar.firstWeekday - 1
        return Array(names[first...] + names[..<first])
    }

    private static let title: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()
}

private struct AraDayCell: View {
    @Environment(\.araScale) private var ui
    let number: Int
    let isSelected: Bool
    let isToday: Bool
    var isMarked = false
    let action: () -> Void
    @StateObject private var hover = AraHover()
    @Environment(\.araHue) private var hue

    var body: some View {
        Button(action: action) {
            Text(String(number))
                .font(.system(size: 10 * ui, weight: isSelected || isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isSelected ? AraPalette.onAccent(in: hue) : AraPalette.ink.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Something is on this day.
                .overlay(alignment: .bottom) {
                    if isMarked {
                        Circle()
                            .fill(isSelected ? AraPalette.onAccent(in: hue) : AraPalette.label(in: hue))
                            .frame(width: 3 * ui, height: 3 * ui)
                            .offset(y: -1 * ui)
                    }
                }
                .background {
                    if isSelected {
                        Capsule().fill(AraPalette.accent(in: hue))
                    } else if hover.isHovered {
                        Capsule().fill(AraPalette.hoverWash)
                    } else if isToday {
                        Capsule().strokeBorder(AraPalette.label(in: hue), lineWidth: 1 * ui)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.94))
        .onHover { hover.isHovered = $0 }
    }
}
