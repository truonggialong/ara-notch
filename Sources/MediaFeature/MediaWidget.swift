import MediaCore
import NotchShell
import SwiftUI

/// What is playing, as a widget of the overview. Small: the artwork, the title and the singer,
/// play and pause, how far it has got. Wide: a bigger artwork, the app, the three buttons and
/// the times. Large: the line being sung, and the volume and the speaker as well.
struct MediaWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    @ObservedObject var model: MediaViewModel
    let onOpen: () -> Void

    private var track: NowPlaying? {
        model.isEnabled ? model.track : nil
    }

    var body: some View {
        AraWidget(name: L10n.string("page.media.title"), hue: .sky, onOpen: onOpen) {
            if let track {
                switch size {
                case .small: small(track)
                case .wide: wide(track)
                case .large: large(track)
                }
            } else {
                empty
            }
        }
    }

    @ViewBuilder
    private var empty: some View {
        let words = VStack(alignment: .leading, spacing: 6 * ui) {
            AraWidgetHeader(label: L10n.string("widget.media.label"))
            Text(L10n.string(model.isUnavailable ? "page.media.unavailable" : "widget.media.empty"))
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        switch size {
        case .small:
            words
        case .wide:
            // The players beside the words: a wide widget has no room for them underneath.
            HStack(spacing: 8 * ui) {
                words
                Spacer(minLength: 0)
                MusicAppLaunchers()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        case .large:
            VStack(alignment: .leading, spacing: 0) {
                words
                Spacer(minLength: 0)
                MusicAppLaunchers()
            }
        }
    }

    private func small(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            HStack(spacing: 7 * ui) {
                artwork(side: 30)
                titles(track, subtitle: track.artist)
                Spacer(minLength: 0)
                playButton(track)
            }
            progress(track, showsTimes: false)
        }
    }

    private func wide(_ track: NowPlaying) -> some View {
        HStack(spacing: 10 * ui) {
            artwork(side: 52)
            VStack(alignment: .leading, spacing: 5 * ui) {
                HStack(spacing: 6 * ui) {
                    titles(track, subtitle: [track.artist, model.sourceApp?.name].compactMap { $0 }.joined(separator: " · "))
                    Spacer(minLength: 0)
                    buttons(track)
                }
                progress(track, showsTimes: true)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func large(_ track: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            HStack(alignment: .top, spacing: 10 * ui) {
                artwork(side: 78)
                VStack(alignment: .leading, spacing: 4 * ui) {
                    AraWidgetHeader(
                        label: L10n.string("widget.media.label"),
                        chip: model.sourceApp.map { AraStatusChip(text: $0.name, hue: .sky) })
                    Text(track.title)
                        .font(.system(size: 14 * ui, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(track.artist ?? "")
                        .font(.system(size: 11 * ui))
                        .foregroundStyle(AraPalette.widgetSecondary)
                        .lineLimit(1)
                    // The line being sung, when the user has lyrics on and the service knows the song.
                    if let lyrics = model.lyrics {
                        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                            let words = track.position(at: timeline.date).flatMap { lyrics.line(at: $0)?.text } ?? ""
                            Text(words.isEmpty ? "♪" : words)
                                .font(.system(size: 11 * ui, weight: .semibold))
                                .foregroundStyle(AraPalette.vivid(.sky))
                                .lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            progress(track, showsTimes: true)
            HStack(spacing: 10 * ui) {
                buttons(track)
                VolumeOverviewRow(model: model)
            }
        }
    }

    private func titles(_ track: NowPlaying, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 1 * ui) {
            Text(track.title)
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(1)
            Text(subtitle ?? "")
                .font(.system(size: 10.5 * ui))
                .foregroundStyle(AraPalette.widgetSecondary)
                .lineLimit(1)
        }
    }

    private func playButton(_ track: NowPlaying) -> some View {
        AraRoundButton(
            icon: track.isPlaying ? .pause : .play, label: L10n.string(track.isPlaying ? "icon.pause" : "icon.play"),
            isPrimary: true, hue: .sky
        ) { model.onCommand?(.togglePlayPause) }
    }

    private func buttons(_ track: NowPlaying) -> some View {
        HStack(spacing: 4 * ui) {
            AraRoundButton(icon: .previous, label: L10n.string("icon.previous"), hue: .sky) {
                model.onCommand?(.previousTrack)
            }
            playButton(track)
            AraRoundButton(icon: .next, label: L10n.string("icon.next"), hue: .sky) {
                model.onCommand?(.nextTrack)
            }
        }
    }

    /// How far the track has got; seeking stays on the music page.
    private func progress(_ track: NowPlaying, showsTimes: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let position = track.position(at: timeline.date)
            HStack(spacing: 6 * ui) {
                if showsTimes {
                    Text(position.map(NowPlaying.clock) ?? "–:––")
                }
                AraTrackBar(fraction: track.progress(at: timeline.date) ?? 0, hue: .sky)
                if showsTimes {
                    Text(remaining(track, at: position))
                }
            }
            .font(.system(size: 10.5 * ui, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(AraPalette.widgetSecondary)
        }
    }

    private func remaining(_ track: NowPlaying, at position: TimeInterval?) -> String {
        guard let duration = track.duration, let position else { return "–:––" }
        return "-" + NowPlaying.clock(max(duration - position, 0))
    }

    @ViewBuilder
    private func artwork(side: CGFloat) -> some View {
        if let picture = model.artwork ?? model.sourceApp?.icon {
            Image(nsImage: picture)
                .resizable()
                .scaledToFill()
                .frame(width: side * ui, height: side * ui)
                .clipShape(RoundedRectangle(cornerRadius: (side > 40 ? 10 : 7) * ui, style: .continuous))
                .accessibilityHidden(true)
        } else {
            AraIcon.music.image
                .font(.system(size: side * 0.4 * ui, weight: .medium))
                .foregroundStyle(AraPalette.vivid(.sky))
                .frame(width: side * ui, height: side * ui)
                .background(AraPalette.widgetQuiet, in: RoundedRectangle(cornerRadius: (side > 40 ? 10 : 7) * ui, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// The volume of the output in use and its name: a line of the music widget and of the device widget.
struct VolumeOverviewRow: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: MediaViewModel

    var body: some View {
        HStack(spacing: 6 * ui) {
            let volume = model.volume ?? 0
            Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10.5 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.widgetSecondary)
                .frame(width: 16 * ui)
                .accessibilityHidden(true)
            AraWidgetSlider(value: Double(volume), hue: .sky, label: L10n.string("page.media.volume")) {
                model.onSetVolume?(Float($0))
            }
            .disabled(model.volume == nil)
            Text(model.outputs.first { $0.id == model.currentOutputID }?.name ?? "")
                .font(.system(size: 10.5 * ui))
                .foregroundStyle(AraPalette.widgetSecondary)
                .lineLimit(1)
                .frame(maxWidth: 90 * ui, alignment: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .onAppear { model.onRefreshVolume?() }
    }
}
