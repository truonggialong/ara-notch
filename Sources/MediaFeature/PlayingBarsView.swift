import SwiftUI

/// A few bars that move while something is playing. They are an animation, not a reading of
/// the actual sound.
struct PlayingBarsView: View {
    @Environment(\.araScale) private var ui
    private static let barCount = 4

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.18)) { timeline in
            let step = Int(timeline.date.timeIntervalSinceReferenceDate / 0.18)
            HStack(alignment: .bottom, spacing: 2 * ui) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .frame(width: 2.5 * ui, height: Self.height(bar: index, step: step))
                }
            }
            .frame(height: 12 * ui, alignment: .bottom)
            .animation(.easeInOut(duration: 0.18), value: step)
        }
    }

    /// A steady pseudo-random height in 3…12 for this bar at this step.
    private static func height(bar: Int, step: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: step &* 31 &+ bar &* 17 &+ 7)
        value ^= value >> 12
        value = value &* 0x9E37_79B9_7F4A_7C15
        value ^= value >> 29
        return 3 + CGFloat(value % 10)
    }
}
