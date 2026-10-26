import Foundation

/// The track the system reports as now playing, in whatever app plays it.
public struct NowPlaying: Equatable, Sendable {
    /// Bundle identifier of the app that plays it.
    public var bundleID: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    /// Position in the track at `timestamp`.
    public var elapsed: TimeInterval?
    /// Playback speed; 0 while paused.
    public var rate: Double
    /// When `elapsed` was measured.
    public var timestamp: Date?
    public var isPlaying: Bool
    /// Changes when the artwork does.
    public var artworkID: String?

    public init(
        bundleID: String?, title: String, artist: String?, album: String?, duration: TimeInterval?,
        elapsed: TimeInterval?, rate: Double, timestamp: Date?, isPlaying: Bool, artworkID: String?
    ) {
        self.bundleID = bundleID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.rate = rate
        self.timestamp = timestamp
        self.isPlaying = isPlaying
        self.artworkID = artworkID
    }

    /// Where the track is at `date`: a playing track advances from its last report, a paused
    /// one stays. Never before the reported position or past the end.
    public func position(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var position = elapsed
        if isPlaying, let timestamp {
            position += max(0, date.timeIntervalSince(timestamp)) * (rate > 0 ? rate : 1)
        }
        if let duration, duration > 0 {
            position = min(position, duration)
        }
        return position
    }

    /// 0…1, when the duration is known.
    public func progress(at date: Date) -> Double? {
        guard let duration, duration > 0, let position = position(at: date) else { return nil }
        return position / duration
    }

    /// The track as it is right after jumping to this share of its length, and the position
    /// in seconds to ask the player for. Nil when the length is not known.
    public func seeking(toFraction fraction: Double, at now: Date) -> (track: NowPlaying, seconds: TimeInterval)? {
        guard let duration, duration > 0 else { return nil }
        let seconds = min(max(fraction, 0), 1) * duration
        var track = self
        track.elapsed = seconds
        track.timestamp = now
        return (track, seconds)
    }

    public func isSameTrack(as other: NowPlaying) -> Bool {
        title == other.title && artist == other.artist && album == other.album
    }

    /// "1:05", or "1:02:05" from an hour on.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// One report from the now-playing helper.
public struct NowPlayingUpdate: Equatable, Sendable {
    /// Nil when nothing has a track to show.
    public var track: NowPlaying?
    /// Image data, sent once each time the artwork changes.
    public var artwork: Data?
    /// The system interface the helper relies on is missing on this macOS.
    public var isUnavailable: Bool
}

/// Reads the helper's output: one JSON object per line.
public enum NowPlayingParser {
    public static func parse(line: String) -> NowPlayingUpdate? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return nil
        }
        if object["unavailable"] as? Bool == true {
            return NowPlayingUpdate(track: nil, artwork: nil, isUnavailable: true)
        }
        // A player that gives no title (QuickTime Player with a plain file) still plays something:
        // the file's name, without its extension, stands in.
        let fileName = text(object["file"]).map { ($0 as NSString).deletingPathExtension }
        // With no name of any kind, something that is playing in a known app is still shown;
        // its title is empty and the page names the app instead.
        let isNamelessButPlaying = object["isPlaying"] as? Bool == true && text(object["bundleID"]) != nil
        guard let title = text(object["title"]) ?? fileName.flatMap({ $0.isEmpty ? nil : $0 })
            ?? (isNamelessButPlaying ? "" : nil)
        else {
            return NowPlayingUpdate(track: nil, artwork: nil, isUnavailable: false)
        }
        let track = NowPlaying(
            bundleID: text(object["bundleID"]), title: title,
            artist: text(object["artist"]), album: text(object["album"]),
            duration: number(object["duration"]), elapsed: number(object["elapsed"]),
            rate: number(object["rate"]) ?? 0,
            timestamp: number(object["timestamp"]).map(Date.init(timeIntervalSince1970:)),
            isPlaying: object["isPlaying"] as? Bool ?? false,
            artworkID: text(object["artworkID"]))
        let artwork = (object["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
        return NowPlayingUpdate(track: track, artwork: artwork, isUnavailable: false)
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func number(_ value: Any?) -> Double? {
        // A JSON boolean is an NSNumber too, but never a duration.
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }
}

/// Playback commands, with the codes the system's media interface uses.
public enum MediaCommand: UInt32, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case stop = 3
    case nextTrack = 4
    case previousTrack = 5
}

/// Reads and writes the Now Playing settings.
public struct MediaSettingsStore {
    public enum Key {
        public static let isEnabled = "media.enabled"
        public static let announcesTracks = "media.announcesTracks"
        public static let showsWhilePlaying = "media.showsWhilePlaying"
        public static let showsLyrics = "media.showsLyrics"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Whether the app reads what is playing at all.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Key.isEnabled) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.isEnabled) }
    }

    /// Whether a new track is announced beside the closed notch.
    public var announcesTracks: Bool {
        get { defaults.object(forKey: Key.announcesTracks) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.announcesTracks) }
    }

    /// Whether the line being sung is shown under the track's name. Off until the user turns
    /// it on: fetching lyrics sends the track's name and artist to a lyrics service.
    public var showsLyrics: Bool {
        get { defaults.object(forKey: Key.showsLyrics) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Key.showsLyrics) }
    }

    /// Whether the artwork and moving bars stay beside the closed notch while something plays.
    public var showsWhilePlaying: Bool {
        get { defaults.object(forKey: Key.showsWhilePlaying) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.showsWhilePlaying) }
    }
}

/// What to do when the helper that reads the player has stopped: start it again a few times,
/// then leave it, so that an interface the system no longer allows cannot cause a restart loop,
/// and say that the player cannot be read.
public struct HelperRestarts: Sendable {
    public enum Action: Equatable, Sendable {
        case restart
        case giveUp
    }

    public let limit: Int
    private var count = 0

    public init(limit: Int) {
        self.limit = limit
    }

    public mutating func afterExit() -> Action {
        guard count < limit else { return .giveUp }
        count += 1
        return .restart
    }

    /// The helper could not be started at all: starting it again would fail the same way.
    public mutating func afterFailedStart() -> Action {
        count = limit
        return .giveUp
    }
}
