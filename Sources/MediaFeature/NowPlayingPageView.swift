import MediaCore
import NotchShell
import SwiftUI

/// The Now Playing page of the notch: the artwork as a card on a small pile of paper, the
/// track beside it, and an outlined bar of playback buttons.
struct NowPlayingPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: MediaViewModel

    var body: some View {
        if !model.isEnabled {
            message("page.media.disabled")
        } else if model.isUnavailable {
            message("page.media.unavailable")
        } else {
            switch NowPlayingView.choose(
                hasTrack: model.track != nil, trackIsPlaying: model.track?.isPlaying ?? false,
                soundingApps: model.otherApps.count) {
            case .track:
                if let track = model.track {
                    player(track)
                }
            case .soundingApps:
                soundOnly
            case .nothing:
                message("page.media.empty")
                    .overlay(alignment: .topTrailing) { outputMenu(look: .outlined) }
                    .overlay(alignment: .bottom) { MusicAppLaunchers() }
            }
        }
    }

    /// Chooses the device sound goes to. Shown with or without a track.
    @ViewBuilder
    private func outputMenu(look: AraButtonLook) -> some View {
        if !model.outputs.isEmpty {
            let current = model.outputs.first { $0.id == model.currentOutputID }
            Menu {
                ForEach(model.outputs) { output in
                    Button {
                        model.onSelectOutput?(output)
                    } label: {
                        Label(output.name, systemImage: output.id == model.currentOutputID ? "checkmark" : output.symbolName)
                    }
                }
            } label: {
                Image(systemName: current?.symbolName ?? AraIcon.output.symbolName)
                    .font(.system(size: 12 * ui, weight: .semibold))
                    .foregroundStyle(AraPalette.ink.opacity(0.88))
                    .frame(width: 28 * ui, height: 28 * ui)
                    .background {
                        if look == .outlined {
                            Circle().strokeBorder(AraPalette.hairline, lineWidth: 1 * ui)
                        }
                    }
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(current.map { String(format: L10n.string("page.media.output"), $0.name) } ?? AraIcon.output.label)
            .accessibilityLabel(AraIcon.output.label)
        }
    }

    private func message(_ key: String) -> some View {
        AraEmptyState(icon: .music, title: L10n.string(key))
    }

    private func player(_ track: NowPlaying) -> some View {
        HStack(spacing: 18 * ui) {
            artworkStack
                .frame(width: 150 * ui)
            VStack(alignment: .leading, spacing: 7 * ui) {
                VStack(alignment: .leading, spacing: 2 * ui) {
                    HStack(spacing: 6 * ui) {
                        // Something with no name of its own is called after the app playing it.
                        Text(track.title.isEmpty ? (model.sourceApp?.name ?? L10n.string("page.media.untitled")) : track.title)
                            .font(AraType.display(16 * ui))
                            .lineLimit(1)
                        if track.isPlaying {
                            PlayingBarsView()
                        }
                        Spacer(minLength: 4 * ui)
                        otherAppIcons
                    }
                    // Which app it plays in, then who and what: APP | artist · album.
                    HStack(spacing: 5 * ui) {
                        if let app = model.sourceApp {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 13 * ui, height: 13 * ui)
                        }
                        let facts = [track.artist, track.album].compactMap { $0 }.filter { !$0.isEmpty }
                        // When the app's name already stands in for the title, it is not said twice.
                        if track.title.isEmpty || (model.sourceApp == nil && facts.isEmpty) {
                            Text(L10n.string("page.media.untitled"))
                                .font(.system(size: 11 * ui))
                                .foregroundStyle(AraTheme.secondaryText)
                                .lineLimit(1)
                        } else if let app = model.sourceApp, !facts.isEmpty {
                            AraFactRow(app.name, facts.joined(separator: " · "))
                        } else {
                            AraLabel(model.sourceApp?.name ?? facts.joined(separator: " · "))
                        }
                    }
                }
                // The line being sung, when the user has lyrics on and the service knows the song.
                if let lyrics = model.lyrics {
                    TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                        let words = track.position(at: timeline.date).flatMap { lyrics.line(at: $0)?.text } ?? ""
                        Text(words.isEmpty ? "♪" : words)
                            .font(.system(size: 12 * ui, weight: .semibold))
                            .foregroundStyle(AraPalette.tint(.sky).ink)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(words)
                            .transition(.opacity)
                            .animation(.easeInOut(duration: 0.25), value: words)
                    }
                }
                // Redrawn every second only while the page is on screen.
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    progress(track, at: timeline.date)
                }
                controls(track)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6 * ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Other apps that are sending sound while the track plays, as small icons that bring
    /// their app forward.
    @ViewBuilder
    private var otherAppIcons: some View {
        if !model.otherApps.isEmpty {
            HStack(spacing: 3 * ui) {
                ForEach(model.otherApps.prefix(4)) { app in
                    SoundingAppIcon(app: app, size: 16 * ui) { model.onOpenApp?(app) }
                }
            }
        }
    }

    /// Nothing says what it plays, but one or more apps are sending sound: a clip in a chat
    /// app, a game, a call. Each is shown by its icon and name; a click brings it forward.
    private var soundOnly: some View {
        VStack(spacing: 10 * ui) {
            HStack(spacing: 10 * ui) {
                ForEach(model.otherApps.prefix(3)) { app in
                    SoundingAppCard(app: app) { model.onOpenApp?(app) }
                }
            }
            .frame(maxHeight: .infinity)
            HStack(spacing: 6 * ui) {
                Text(L10n.string("page.media.soundOnly"))
                    .font(.system(size: 11 * ui))
                    .foregroundStyle(AraTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0 * ui)
                volumeSlider
                outputMenu(look: .bare)
            }
            .padding(.horizontal, 12 * ui)
            .frame(height: 38 * ui)
            .araSurface(Capsule())
        }
        .padding(.horizontal, 6 * ui)
        .onAppear { model.onRefreshVolume?() }
    }

    @ViewBuilder
    private var volumeSlider: some View {
        if let volume = model.volume {
            Image(systemName: volume <= 0.001 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11 * ui, weight: .semibold))
                .foregroundStyle(AraTheme.secondaryText)
                .frame(width: 18 * ui)
            AraSlider(value: Double(volume)) { model.onSetVolume?(Float($0)) }
                .frame(width: 84 * ui)
                .accessibilityLabel(L10n.string("page.media.volume"))
        }
    }

    /// The artwork on top of two blank cards, fanned out like cards in a hand.
    private var artworkStack: some View {
        ZStack {
            Color.clear
                .frame(width: 82 * ui, height: 82 * ui)
                .araCard()
                .rotationEffect(.degrees(-10))
                .offset(x: -28 * ui, y: 6)
            Color.clear
                .frame(width: 82 * ui, height: 82 * ui)
                .araCard()
                .rotationEffect(.degrees(10))
                .offset(x: 28 * ui, y: 6)
            artworkCard
                .frame(width: 98 * ui, height: 98 * ui)
        }
    }

    private var artworkCard: some View {
        artwork
            .clipShape(RoundedRectangle(cornerRadius: 14 * ui, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14 * ui, style: .continuous)
                    .strokeBorder(AraPalette.hairline, lineWidth: 1 * ui)
            }
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = model.artwork {
            Color.clear.overlay {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else if let app = model.sourceApp {
            // No artwork: the app that plays stands in for it.
            AraPalette.cardRaised.overlay {
                Image(nsImage: app.icon)
                    .resizable()
                    .scaledToFit()
                    .padding(16 * ui)
            }
        } else {
            AraPalette.cardRaised.overlay {
                AraIcon.music.image
                    .font(.system(size: 26 * ui))
                    .foregroundStyle(AraPalette.label)
            }
        }
    }

    /// The line can be dragged to another place in the track; the time on the left follows
    /// the pointer while it is.
    private func progress(_ track: NowPlaying, at date: Date) -> some View {
        let fraction = model.scrubFraction ?? track.progress(at: date) ?? 0
        let shown = model.scrubFraction.flatMap { fraction in track.duration.map { $0 * fraction } } ?? track.position(at: date)
        return HStack(spacing: 8 * ui) {
            Text(shown.map(NowPlaying.clock) ?? "–:––")
            if track.duration ?? 0 > 0 {
                AraSlider(value: fraction) { model.scrubFraction = $0 } onEnded: { model.onSeek?($0) }
            } else {
                AraProgressLine(fraction: fraction)
            }
            Text(track.duration.map(NowPlaying.clock) ?? "–:––")
        }
        .font(.system(size: 10 * ui, design: .monospaced))
        .foregroundStyle(AraTheme.secondaryText)
        .onAppear { model.onRefreshVolume?() }
        .onChange(of: date) { _, _ in model.onRefreshVolume?() }
    }

    /// One outlined bar: the three playback buttons, the volume, and at its end where the sound goes.
    private func controls(_ track: NowPlaying) -> some View {
        HStack(spacing: 6 * ui) {
            AraIconButton(.previous, look: .bare) { model.onCommand?(.previousTrack) }
            AraIconButton(track.isPlaying ? .pause : .play, look: .accent, size: .regular) {
                model.onCommand?(.togglePlayPause)
            }
            AraIconButton(.next, look: .bare) { model.onCommand?(.nextTrack) }
            Spacer(minLength: 0 * ui)
            volumeSlider
            outputMenu(look: .bare)
        }
        .padding(.horizontal, 8 * ui)
        .frame(height: 42 * ui)
        .araSurface(Capsule())
    }
}

/// An app that is sending sound, as an icon: its name is the tooltip, a click brings it forward.
private struct SoundingAppIcon: View {
    @Environment(\.araScale) private var ui
    let app: SoundingApp
    let size: CGFloat
    let action: () -> Void
    @StateObject private var hover = AraHover()

    var body: some View {
        Button(action: action) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: size, height: size)
                .scaleEffect(hover.isHovered ? 1.15 : 1)
                .animation(AraTheme.hover, value: hover.isHovered)
        }
        .buttonStyle(AraPressStyle())
        .onHover { hover.isHovered = $0 }
        .araTooltip(String(format: L10n.string("page.media.alsoPlaying"), app.name), isHovered: hover.isHovered)
        .accessibilityLabel(String(format: L10n.string("page.media.alsoPlaying"), app.name))
    }
}

/// An app that is sending sound, as a card: icon, name, and bars that move while it plays.
private struct SoundingAppCard: View {
    @Environment(\.araScale) private var ui
    let app: SoundingApp
    let action: () -> Void

    var body: some View {
        AraHoverLift(scale: 1.03) { isHovered in
            Button(action: action) {
                HStack(spacing: 10 * ui) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 40 * ui, height: 40 * ui)
                    VStack(alignment: .leading, spacing: 3 * ui) {
                        Text(app.name)
                            .font(.system(size: 12 * ui, weight: .semibold))
                            .lineLimit(1)
                        PlayingBarsView()
                    }
                }
                .padding(.horizontal, 12 * ui)
                .frame(height: 62 * ui)
                .frame(minWidth: 150 * ui, alignment: .leading)
                .araCard(level: isHovered ? .raised : .plate)
                .contentShape(RoundedRectangle(cornerRadius: AraTheme.cardRadius * ui, style: .continuous))
            }
            .buttonStyle(AraPressStyle(depth: 0.97))
            .araTooltip(String(format: L10n.string("page.agents.open"), app.name), isHovered: isHovered)
        }
    }
}

/// With nothing playing, the players on this Mac, one click from starting.
struct MusicAppLaunchers: View {
    @Environment(\.araScale) private var ui
    private struct Player: Identifiable {
        let id: String
        let name: String
        let url: URL
        let icon: NSImage
    }

    private static let players: [Player] = {
        let workspace = NSWorkspace.shared
        let installed = Set(MusicApps.known.filter { workspace.urlForApplication(withBundleIdentifier: $0) != nil })
        return MusicApps.offered(installed: installed).compactMap { id in
            guard let url = workspace.urlForApplication(withBundleIdentifier: id) else { return nil }
            let icon = workspace.icon(forFile: url.path)
            icon.size = NSSize(width: 22, height: 22)
            return Player(id: id, name: FileManager.default.displayName(atPath: url.path), url: url, icon: icon)
        }
    }()

    var body: some View {
        HStack(spacing: 8 * ui) {
            ForEach(Self.players) { player in
                MusicAppButton(name: player.name, icon: player.icon) {
                    NSWorkspace.shared.openApplication(at: player.url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
        }
    }
}

private struct MusicAppButton: View {
    @Environment(\.araScale) private var ui
    let name: String
    let icon: NSImage
    let action: () -> Void
    @StateObject private var hover = AraHover()

    var body: some View {
        let title = String(format: L10n.string("page.media.open"), name)
        Button(action: action) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22 * ui, height: 22 * ui)
                .frame(width: 30 * ui, height: 30 * ui)
                .background(hover.isHovered ? AraPalette.hoverWash : .clear, in: RoundedRectangle(cornerRadius: 9 * ui, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle())
        .onHover { hover.isHovered = $0 }
        .araTooltip(title, isHovered: hover.isHovered)
        .accessibilityLabel(title)
    }
}
