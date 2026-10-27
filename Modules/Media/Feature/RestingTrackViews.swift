import MediaCore
import NotchShell
import SwiftUI

/// The playing track's artwork on the left of the closed notch; dimmed while paused. A click
/// on it opens the Now Playing page.
struct RestingArtwork: View {
    @ObservedObject var model: MediaViewModel
    let picture: NSImage?
    let colors: [Color]
    let onOpen: () -> Void

    var body: some View {
        let isPlaying = model.track?.isPlaying ?? false
        Button(action: onOpen) {
            Group {
                if let picture {
                    Image(nsImage: picture)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                }
            }
            .opacity(isPlaying ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.3), value: isPlaying)
    }
}

/// The bars on the right of the closed notch, in the track's colours. They move while it
/// plays and lie flat as dots while it is paused. With the pointer on them they become the
/// button that pauses or plays: two of them stand as the pause sign, or a play sign shows.
/// They are an animation, not a reading of the actual sound.
struct RestingBars: View {
    @ObservedObject var model: MediaViewModel
    let colors: [Color]
    @Environment(\.notchActivityIsHovered) private var isHovered

    private static let count = 5
    private static let tallest: CGFloat = 16
    private static let interval = 0.18

    var body: some View {
        let isPlaying = model.track?.isPlaying ?? false
        let moves = isPlaying && !isHovered
        Button { model.onCommand?(.togglePlayPause) } label: {
            TimelineView(.animation(minimumInterval: Self.interval, paused: !moves)) { timeline in
                let step = moves ? Int(timeline.date.timeIntervalSinceReferenceDate / Self.interval) : 0
                ZStack {
                    HStack(spacing: 2) {
                        ForEach(0..<Self.count, id: \.self) { index in
                            let bar = Self.bar(index, step: step, isPlaying: isPlaying, isHovered: isHovered)
                            Capsule()
                                .frame(width: bar.width, height: bar.height)
                                .opacity(bar.opacity)
                        }
                    }
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .scaleEffect(isHovered && !isPlaying ? 1 : 0.4)
                        .opacity(isHovered && !isPlaying ? 1 : 0)
                }
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
                .animation(.easeInOut(duration: Self.interval), value: step)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isHovered)
        .animation(.easeOut(duration: 0.3), value: isPlaying)
    }

    private struct Bar {
        var width: CGFloat
        var height: CGFloat
        var opacity: Double
    }

    /// The second and fourth bars stand as the pause sign; the play sign replaces them all.
    private static func bar(_ index: Int, step: Int, isPlaying: Bool, isHovered: Bool) -> Bar {
        if isHovered {
            let isSign = isPlaying && (index == 1 || index == 3)
            return isSign ? Bar(width: 4, height: 14, opacity: 1) : Bar(width: 0, height: 0, opacity: 0)
        }
        guard isPlaying else { return Bar(width: 3, height: 3, opacity: 0.55) }
        return Bar(width: 3, height: height(bar: index, step: step), opacity: 1)
    }

    /// A steady pseudo-random height in 3…16 for this bar at this step.
    private static func height(bar: Int, step: Int) -> CGFloat {
        var value = UInt64(truncatingIfNeeded: step &* 31 &+ bar &* 17 &+ 7)
        value ^= value >> 12
        value = value &* 0x9E37_79B9_7F4A_7C15
        value ^= value >> 29
        return 3 + CGFloat(value % UInt64(tallest - 2))
    }
}

/// How far the track has played, as a short line under the hardware notch: the part played
/// runs through the track's colours and glows in them while it plays. With the pointer on the
/// notch's sides or on the line, it grows, shows the times, and a click or drag on it seeks.
struct TrackProgressLine: View {
    @ObservedObject var model: MediaViewModel
    let colors: [Color]
    @Environment(\.notchActivityIsHovered) private var isHovered

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let track = model.track
            // The share of the track under the pointer while the line is being dragged.
            let scrub = model.scrubFraction
            let isPlaying = track?.isPlaying ?? false
            let played = scrub ?? track?.progress(at: timeline.date) ?? 0
            let width: CGFloat = isHovered ? 150 : 80
            let thickness: CGFloat = isHovered ? 6 : 3
            HStack(spacing: 8) {
                if isHovered {
                    time((track?.duration ?? 0) * played)
                        .frame(width: 36, alignment: .trailing)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(thickness, width * played))
                        .opacity(isPlaying || scrub != nil ? 1 : 0.6)
                        .shadow(color: isPlaying ? colors.first?.opacity(0.85) ?? .clear : .clear, radius: 3)
                    if isHovered {
                        Circle()
                            .fill(.white)
                            .frame(width: 10, height: 10)
                            .offset(x: width * played - 5)
                    }
                }
                .frame(width: width, height: thickness)
                .animation(scrub == nil ? .linear(duration: 0.5) : nil, value: played)
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { model.scrubFraction = Self.share(of: $0.location.x, in: width) }
                        .onEnded { model.onSeek?(Self.share(of: $0.location.x, in: width)) },
                    including: isHovered ? .all : .none)
                if isHovered {
                    time(track?.duration ?? 0)
                        .frame(width: 36, alignment: .leading)
                }
            }
        }
    }

    private func time(_ seconds: TimeInterval) -> some View {
        Text(NowPlaying.clock(seconds))
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
    }

    private static func share(of x: CGFloat, in width: CGFloat) -> Double {
        Double(min(max(x / width, 0), 1))
    }
}
