import AppKit
import Combine
import MediaCore
import NotchShell
import SwiftUI

/// State the Now Playing page renders from.
@MainActor
final class MediaViewModel: ObservableObject {
    @Published var track: NowPlaying?
    @Published var artwork: NSImage?
    /// The timed words of the track, when lyrics are on and were found.
    @Published var lyrics: Lyrics?
    @Published var isEnabled = true
    /// The system interface for reading the track is missing on this macOS.
    @Published var isUnavailable = false

    /// The devices sound can go to, and the one in use.
    @Published var outputs: [AudioOutput] = []
    @Published var currentOutputID: UInt32?

    var onCommand: ((MediaCommand) -> Void)?
    /// The share of the track under the pointer while the progress line is being dragged.
    @Published var scrubFraction: Double?
    /// Jump to this share of the track.
    var onSeek: ((Double) -> Void)?
    /// The output's volume, 0…1; nil when the device has none to set.
    @Published var volume: Float?
    var onSetVolume: ((Float) -> Void)?
    var onRefreshVolume: (() -> Void)?
    var onSelectOutput: ((AudioOutput) -> Void)?

    /// The app the track on the page plays in.
    @Published var sourceApp: SoundingApp?
    /// Other apps sending sound out right now: a video in a chat app, a second player.
    @Published var otherApps: [SoundingApp] = []
    /// Bring this app forward.
    var onOpenApp: ((SoundingApp) -> Void)?
}

/// Shows what is playing on the notch and controls it.
@MainActor
public final class MediaController {
    private static let activityID = "media.track"
    private static let restingActivityID = "media.playing"
    /// The track whose lyrics were last asked for, and the request under way.
    private var lyricsKey: String?
    private var lyricsTask: Task<Void, Never>?
    /// What the resting activity was last drawn from, so it is set again only on a change.
    private var restingKey: String?

    private let settings: MediaSettings
    private let notch: NotchController
    private let viewModel = MediaViewModel()
    private let helper = NowPlayingHelper()
    private let soundMonitor = SoundingAppsMonitor()
    /// The apps sending sound, as last reported.
    private var soundingBundleIDs: [String] = []
    /// When each app was last named beside the notch, so it is not named over and over.
    private var announcedApps: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    /// False while updates are fed in by a test instead of the helper.
    private var usesHelper = true

    public init(settings: MediaSettings, notch: NotchController) {
        self.settings = settings
        self.notch = notch
        viewModel.onCommand = { [weak self] command in self?.send(command) }
        viewModel.onSeek = { [weak self] fraction in self?.seek(toFraction: fraction) }
        viewModel.onSetVolume = { [weak self] volume in
            AudioOutputs.volume = volume
            self?.viewModel.volume = volume
        }
        viewModel.onRefreshVolume = { [weak self] in
            let volume = AudioOutputs.volume
            if self?.viewModel.volume != volume {
                self?.viewModel.volume = volume
            }
        }
        helper.onUpdate = { [weak self] update in self?.apply(update) }
        // The player cannot be read on this Mac: the page says so instead of "nothing playing".
        helper.onGaveUp = { [weak self] in self?.viewModel.isUnavailable = true }
        soundMonitor.onChange = { [weak self] bundleIDs in
            self?.soundingBundleIDs = bundleIDs
            self?.refreshOtherApps(announcing: true)
        }
        viewModel.onOpenApp = { [weak self] app in
            NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration())
            self?.notch.close()
        }
        viewModel.onSelectOutput = { [weak self] output in
            if !AudioOutputs.select(output.id) {
                NSSound.beep()
            }
            self?.refreshOutputs()
        }
    }

    /// Starts reading, and follows the setting from then on.
    public func start() {
        settings.$isEnabled
            .sink { [weak self] isEnabled in self?.setEnabled(isEnabled) }
            .store(in: &cancellables)
        // The published value is the old one while the setting is being written.
        settings.$showsWhilePlaying
            .sink { [weak self] shows in self?.refreshRestingActivity(shows: shows) }
            .store(in: &cancellables)
        settings.$showsLyrics
            .sink { [weak self] shows in self?.refreshLyrics(shows: shows) }
            .store(in: &cancellables)
        // Devices come and go; the list is read again each time the notch opens.
        notch.isOpenPublisher
            .filter { $0 }
            .sink { [weak self] _ in
                self?.refreshOutputs()
                self?.soundMonitor.refresh()
            }
            .store(in: &cancellables)
        refreshOutputs()
    }

    /// Works out which sounding apps to list beside the track, and names a newly sounding
    /// one beside the closed notch.
    private func refreshOtherApps(announcing: Bool) {
        let playing = viewModel.track.flatMap { $0.isPlaying ? $0.bundleID : nil }
        let own = Bundle.main.bundleIdentifier ?? ""
        let apps = SoundingApps.others(sounding: soundingBundleIDs, playingBundleID: playing, own: own)
            .compactMap(SoundingApp.lookUp(bundleID:))
        let appeared = apps.filter { !viewModel.otherApps.contains($0) }
        if apps != viewModel.otherApps {
            viewModel.otherApps = apps
        }
        guard announcing, settings.announcesTracks else { return }
        let now = Date()
        for app in appeared where now.timeIntervalSince(announcedApps[app.bundleID] ?? .distantPast) > 120 {
            announcedApps[app.bundleID] = now
            announce(app)
        }
    }

    /// Says beside the closed notch that an app started playing something it gives no name for.
    private func announce(_ app: SoundingApp) {
        notch.present(NotchLiveActivity(
            id: Self.activityID, priority: 1, duration: 3, pageID: "media",
            sign: AraSign(
                icon: .image(app.icon), mark: L10n.string("page.media.title"),
                rows: [AraSign.Row(app.name, detail: L10n.string("sign.media.sounding"))])))
    }

    private func refreshOutputs() {
        viewModel.outputs = AudioOutputs.all()
        viewModel.currentOutputID = AudioOutputs.current()
    }

    /// Names of the output devices, the one in use first; for diagnostics.
    public var outputSummary: String {
        refreshOutputs()
        return viewModel.outputs
            .map { ($0.id == viewModel.currentOutputID ? "* " : "  ") + "\($0.name) [\($0.transport)] \($0.symbolName)" }
            .joined(separator: "\n")
    }

    public func stop() {
        helper.stop()
        soundMonitor.stop()
    }

    /// The volume and the output in use, as one line of the overview page's device tile.
    public func makeVolumeRow() -> AnyView {
        AnyView(VolumeOverviewRow(model: viewModel))
    }

    /// What is playing, as a tile of the overview page.
    public func makeOverviewTile() -> AnyView {
        AnyView(MediaWidget(model: viewModel) { [weak notch] in notch?.selectPage(id: "media") })
    }


    public func makePage() -> NotchPage {
        var page = NotchPage(
            id: "media", titleKey: "page.media.title", symbolName: AraIcon.music.symbolName, hue: .sky
        ) { [viewModel] in
            NowPlayingPageView(model: viewModel)
        }
        // From the keyboard: Space plays and pauses, the arrows change track.
        page.keyHandler = { [weak self] key, isTyping in
            guard let self, !isTyping, self.viewModel.track != nil else { return false }
            switch key {
            case .space, .confirm: self.send(.togglePlayPause)
            case .left: self.send(.previousTrack)
            case .right: self.send(.nextTrack)
            default: return false
            }
            return true
        }
        return page
    }

    /// What the music page reads, for Settings › Notch pages.
    public func makePageSettings() -> AnyView {
        AnyView(MediaPageSettings(settings: settings))
    }

    /// What is shown beside the notch about music, for Settings › Notices.
    public func makeNoticeSettings() -> AnyView {
        AnyView(MediaNoticeSettings(settings: settings))
    }

    /// Feeds one line of helper output, as if the helper had printed it. The real helper is
    /// not used from then on.
    public func simulate(line: String) {
        usesHelper = false
        helper.stop()
        if let update = NowPlayingParser.parse(line: line) {
            apply(update)
        }
    }

    /// Shows these apps as sending sound, as if the audio system had reported them. The real
    /// reports are not used from then on.
    public func simulate(soundingBundleIDs: [String]) {
        usesHelper = false
        helper.stop()
        soundMonitor.stop()
        soundingBundleIDs.isEmpty ? () : (self.soundingBundleIDs = soundingBundleIDs)
        refreshOtherApps(announcing: false)
    }

    private func setEnabled(_ isEnabled: Bool) {
        viewModel.isEnabled = isEnabled
        if isEnabled {
            if usesHelper {
                helper.start()
                soundMonitor.start()
            }
        } else {
            helper.stop()
            soundMonitor.stop()
            viewModel.track = nil
            viewModel.artwork = nil
            notch.dismissActivity(id: Self.activityID)
            refreshRestingActivity(shows: false)
        }
    }

    /// Fetches the timed lyrics of the track that is playing, once per track, and only while
    /// the user has lyrics turned on: the track's name and artist go to the lyrics service.
    private func refreshLyrics(shows: Bool) {
        guard shows, settings.isEnabled, let track = viewModel.track, !track.title.isEmpty else {
            lyricsTask?.cancel()
            lyricsKey = nil
            if viewModel.lyrics != nil {
                viewModel.lyrics = nil
            }
            return
        }
        let key = "\(track.title)|\(track.artist ?? "")"
        guard key != lyricsKey else { return }
        lyricsKey = key
        lyricsTask?.cancel()
        viewModel.lyrics = nil
        guard let request = LyricsService.request(
            title: track.title, artist: track.artist, album: track.album, duration: track.duration)
        else { return }
        lyricsTask = Task { [weak self] in
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, !Task.isCancelled
            else { return }
            let lyrics = LyricsService.lyrics(from: data)
            guard let self, self.lyricsKey == key else { return }
            self.viewModel.lyrics = lyrics
        }
    }

    /// While something plays, its artwork and moving bars rest beside the closed notch;
    /// anything announced for a moment shows over them and they come back after.
    private func refreshRestingActivity(shows: Bool) {
        guard shows, settings.isEnabled, let track = viewModel.track, track.isPlaying else {
            if restingKey != nil {
                restingKey = nil
                notch.setRestingActivity(nil, id: Self.restingActivityID)
            }
            return
        }
        // Set again only when what it draws has changed: the track, or its artwork arriving.
        let key = "\(track.artworkID ?? track.title)|\(viewModel.artwork != nil)|\(viewModel.sourceApp?.bundleID ?? "")"
        guard key != restingKey else { return }
        restingKey = key
        let artwork = viewModel.artwork
        let icon = viewModel.sourceApp?.icon
        var activity = NotchLiveActivity(id: Self.restingActivityID, priority: 0, duration: 0, pageID: "media") {
            if let picture = artwork ?? icon {
                Image(nsImage: picture)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .medium))
            }
        } trailing: {
            PlayingBarsView()
                .foregroundStyle(AraPalette.tint(.sky).line)
        }
        activity.peek = [track.title, track.artist ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
        // Fingers moving left bring the next track, as they bring the next page.
        activity.onSwipe = { direction in
            MediaCommands.send(direction == .next ? .nextTrack : .previousTrack)
        }
        notch.setRestingActivity(activity, id: Self.restingActivityID)
    }

    private func apply(_ update: NowPlayingUpdate) {
        guard settings.isEnabled else { return }
        viewModel.isUnavailable = update.isUnavailable
        let previous = viewModel.track
        viewModel.track = update.track
        let source = update.track?.bundleID.flatMap(SoundingApp.lookUp(bundleID:))
        if source != viewModel.sourceApp {
            viewModel.sourceApp = source
        }
        // The app whose track is on the page is not listed a second time among the others.
        refreshOtherApps(announcing: false)

        if let data = update.artwork {
            viewModel.artwork = NSImage(data: data)
        } else if update.track?.artworkID != previous?.artworkID {
            // Another track whose artwork was not sent (yet): do not keep showing the old one.
            viewModel.artwork = nil
        }

        refreshRestingActivity(shows: settings.showsWhilePlaying)
        refreshLyrics(shows: settings.showsLyrics)
        guard let track = update.track, track.isPlaying else { return }
        let isNewTrack = previous.map { !$0.isSameTrack(as: track) } ?? true
        if isNewTrack, settings.announcesTracks {
            announce(track)
        }
    }

    /// Names a track that just started beside the closed notch.
    private func announce(_ track: NowPlaying) {
        let artwork = viewModel.artwork
        let source = viewModel.sourceApp
        // The track is the news; its app need not be named again as "also playing".
        if let bundleID = track.bundleID {
            announcedApps[bundleID] = Date()
        }
        let title = track.title.isEmpty ? (source?.name ?? "") : track.title
        notch.present(NotchLiveActivity(
            id: Self.activityID, priority: 1, duration: 3, pageID: "media",
            sign: AraSign(
                icon: artwork.map { .image($0) } ?? .symbol("music.note"),
                mark: source?.name ?? L10n.string("page.media.title"),
                rows: [AraSign.Row(title, detail: track.artist)])))
    }

    private func seek(toFraction fraction: Double) {
        viewModel.scrubFraction = nil
        guard let seek = viewModel.track?.seeking(toFraction: fraction, at: Date()), MediaCommands.seek(to: seek.seconds) else {
            NSSound.beep()
            return
        }
        // Show the new position at once; the helper confirms it within a second.
        viewModel.track = seek.track
    }

    private func send(_ command: MediaCommand) {
        guard MediaCommands.send(command) else {
            NSSound.beep()
            return
        }
        // Show the new state at once; the helper confirms it within a second.
        if command == .togglePlayPause, var track = viewModel.track {
            if let position = track.position(at: Date()) {
                track.elapsed = position
                track.timestamp = Date()
            }
            track.isPlaying.toggle()
            viewModel.track = track
        }
    }
}
