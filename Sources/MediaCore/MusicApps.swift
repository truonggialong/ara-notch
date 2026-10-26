import Foundation

/// The apps offered for a start when nothing is playing.
public enum MusicApps {
    /// Bundle identifiers of players, in the order they are offered. The system's own player
    /// comes last: it is on every Mac, wanted or not.
    public static let known = [
        "com.spotify.client", "com.tidal.desktop", "com.deezer.deezer-desktop", "org.videolan.vlc",
        "com.colliderli.iina", "com.apple.podcasts", "com.apple.Music",
    ]

    public static let limit = 4

    /// The players to offer among those installed, at most `limit`.
    public static func offered(installed: Set<String>) -> [String] {
        Array(known.filter(installed.contains).prefix(limit))
    }
}
