import Foundation

/// The rules of the app's updates that need no updater to state: when it runs, which feed it
/// may be pointed at by hand, and how releases are named where they are published.
public enum AppUpdatePolicy {
    /// The updater runs in the user's own app. A copy started for an automated check, with
    /// data of its own, leaves updates alone unless it was given a feed to try.
    public static func runsUpdater(isTestRun: Bool, feedOverride: String?) -> Bool {
        !isTestRun || feed(from: feedOverride) != nil
    }

    /// A feed given on the command line, for trying an update before it is published: a
    /// secure address, or a server on this very Mac. From anywhere else updates are never
    /// fetched in the clear, and the updater reads no files.
    public static func feed(from text: String?) -> URL? {
        guard let text, let url = URL(string: text), let host = url.host else { return nil }
        switch url.scheme {
        case "https": return url
        case "http": return ["127.0.0.1", "localhost"].contains(host) ? url : nil
        default: return nil
        }
    }

    /// The tag a version is released under.
    public static func tag(forVersion version: String) -> String {
        "v" + version
    }

    /// Where the app reads what the newest release is: a file attached to whichever release
    /// is the latest.
    public static func feedAddress(owner: String, repository: String) -> String {
        "https://github.com/\(owner)/\(repository)/releases/latest/download/appcast.xml"
    }

    /// Where the files of one release are downloaded from.
    public static func downloadPrefix(owner: String, repository: String, version: String) -> String {
        "https://github.com/\(owner)/\(repository)/releases/download/\(tag(forVersion: version))/"
    }
}
