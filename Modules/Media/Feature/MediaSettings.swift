import Combine
import MediaCore
import NotchShell
import SwiftUI

/// Observable Now Playing settings; every change is written through to the store.
@MainActor
public final class MediaSettings: ObservableObject {
    private let store: MediaSettingsStore

    @Published public var isEnabled: Bool {
        didSet { store.isEnabled = isEnabled }
    }

    @Published public var announcesTracks: Bool {
        didSet { store.announcesTracks = announcesTracks }
    }

    @Published public var showsWhilePlaying: Bool {
        didSet { store.showsWhilePlaying = showsWhilePlaying }
    }

    @Published public var showsLyrics: Bool {
        didSet { store.showsLyrics = showsLyrics }
    }

    public init(store: MediaSettingsStore) {
        self.store = store
        showsLyrics = store.showsLyrics
        isEnabled = store.isEnabled
        announcesTracks = store.announcesTracks
        showsWhilePlaying = store.showsWhilePlaying
    }
}

/// The music page's lines in Settings › Notch pages: reading what plays, and lyrics.
struct MediaPageSettings: View {
    @ObservedObject var settings: MediaSettings

    var body: some View {
        Toggle(isOn: $settings.isEnabled) {
            Text(L10n.string("settings.media.enabled"))
            AraSettingsNote(L10n.string("settings.media.enabled.note"))
        }
        Toggle(isOn: $settings.showsLyrics) {
            Text(L10n.string("settings.media.lyrics"))
            AraSettingsNote(L10n.string("settings.media.lyrics.note"))
        }
        .disabled(!settings.isEnabled)
    }
}

/// The music's lines in Settings › Notices: a new track, and the cover beside the notch.
struct MediaNoticeSettings: View {
    @ObservedObject var settings: MediaSettings

    var body: some View {
        Group {
            Toggle(L10n.string("settings.media.announce"), isOn: $settings.announcesTracks)
            Toggle(L10n.string("settings.media.whilePlaying"), isOn: $settings.showsWhilePlaying)
        }
        .disabled(!settings.isEnabled)
    }
}
