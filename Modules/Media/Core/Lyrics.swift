import Foundation

/// The words of a song with the moment each line is sung.
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        /// Seconds from the start of the track.
        public let time: TimeInterval
        /// Empty for a pause between verses.
        public let text: String
    }

    /// In the order they are sung.
    public let lines: [Line]

    /// Reads lyrics in the LRC form, "[mm:ss.xx] words" a line. A line may carry several
    /// times; lines without a time (titles, credits, plain text) are skipped.
    public init(synced: String) {
        var lines: [Line] = []
        for raw in synced.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw).drop(while: \.isWhitespace)
            var times: [TimeInterval] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                guard let time = Self.seconds(rest[rest.index(after: rest.startIndex)..<close]) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }
        self.lines = lines.sorted { $0.time < $1.time }
    }

    /// "01:05.25" as seconds; nil for a tag that is not a time, such as "ti:Title".
    private static func seconds(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return TimeInterval(minutes * 60) + seconds
    }

    /// The line being sung at a position in the track: the last one that has started.
    public func line(at position: TimeInterval) -> Line? {
        lines.last { $0.time <= position }
    }

    /// The line that comes after the one being sung.
    public func next(after position: TimeInterval) -> Line? {
        lines.first { $0.time > position }
    }
}

/// Asks lrclib.net, a free lyrics service, for the timed lyrics of a track. The track's
/// name, artist, album and length are what is sent.
public enum LyricsService {
    public static func request(title: String, artist: String?, album: String?, duration: TimeInterval?) -> URLRequest? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !artist.isEmpty, var components = URLComponents(string: "https://lrclib.net/api/get") else {
            return nil
        }
        var items = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if let album, !album.isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        if let duration, duration > 0 {
            items.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded()))))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("AraNotch (macOS notch app)", forHTTPHeaderField: "User-Agent")
        return request
    }

    /// The timed lyrics in the service's answer; nil when it has none for the track.
    public static func lyrics(from data: Data) -> Lyrics? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let synced = object["syncedLyrics"] as? String
        else { return nil }
        let lyrics = Lyrics(synced: synced)
        return lyrics.lines.isEmpty ? nil : lyrics
    }
}
