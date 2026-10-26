import Foundation

/// Working out which apps are sending sound out, from what the audio system reports.
public enum SoundingApps {
    /// The app a sounding process belongs to, by bundle id: a browser or an Electron app
    /// plays through helper processes named after it.
    public static func owner(ofBundleID bundleID: String) -> String {
        guard let range = bundleID.range(of: ".helper", options: .caseInsensitive) else { return bundleID }
        return String(bundleID[..<range.lowerBound])
    }

    /// The apps to list beside what the page already shows: each once, in a steady order,
    /// without this app and without the app whose track is on the page.
    public static func others(sounding: [String], playingBundleID: String?, own: String) -> [String] {
        Set(sounding).subtracting([own, playingBundleID].compactMap { $0 }).sorted()
    }
}

/// Keeps short sounds out of the list. A notification blip is not "playing"; a video is. And a
/// player that falls silent for a moment between two clips keeps its place.
public struct SoundDebounce: Equatable, Sendable {
    /// How long an app must have been sounding before it counts.
    public static let minimum: TimeInterval = 2
    /// How long an app that counted stays listed after it falls silent.
    public static let grace: TimeInterval = 3

    private struct Run: Equatable, Sendable {
        var since: Date
        var stoppedAt: Date?
    }

    private var runs: [String: Run] = [:]

    public init() {}

    /// Takes in the apps sounding at this moment.
    public mutating func update(sounding: [String], at now: Date) {
        let current = Set(sounding)
        for app in current {
            if var run = runs[app] {
                // Back within the grace time: the same run goes on.
                run.stoppedAt = nil
                runs[app] = run
            } else {
                runs[app] = Run(since: now, stoppedAt: nil)
            }
        }
        for (app, run) in runs where !current.contains(app) {
            if let stoppedAt = run.stoppedAt {
                if now.timeIntervalSince(stoppedAt) > Self.grace {
                    runs[app] = nil
                }
            } else if now.timeIntervalSince(run.since) < Self.minimum {
                // Over before it ever counted.
                runs[app] = nil
            } else {
                runs[app]?.stoppedAt = now
            }
        }
    }

    /// The apps that count as playing at this moment, in a steady order.
    public func steady(at now: Date) -> [String] {
        runs.filter { _, run in
            if let stoppedAt = run.stoppedAt {
                return now.timeIntervalSince(stoppedAt) <= Self.grace
            }
            return now.timeIntervalSince(run.since) >= Self.minimum
        }
        .keys.sorted()
    }

    /// The next moment the answer of `steady` can change by itself, if there is one.
    public func nextCheck(after now: Date) -> Date? {
        runs.values.compactMap { run -> Date? in
            let moment = run.stoppedAt.map { $0.addingTimeInterval(Self.grace) } ?? run.since.addingTimeInterval(Self.minimum)
            return moment > now ? moment : nil
        }
        .min()
    }
}

/// What the Now Playing page shows.
public enum NowPlayingView: Equatable, Sendable {
    /// The track the system names, with its controls.
    case track
    /// The apps that are sending sound, when no playing track speaks for them.
    case soundingApps
    case nothing

    /// A playing track comes first. A paused one gives way to apps that are sounding: the
    /// system goes on naming a clip paused long ago while another app is the one playing.
    public static func choose(hasTrack: Bool, trackIsPlaying: Bool, soundingApps: Int) -> NowPlayingView {
        if hasTrack, trackIsPlaying { return .track }
        if soundingApps > 0 { return .soundingApps }
        return hasTrack ? .track : .nothing
    }
}
