import Foundation

/// Decides which copied links may be fetched automatically to build a preview.
///
/// Fetching a URL is not always harmless: it can consume a one-time link, trigger an action, or
/// reach a device on the local network. This policy refuses the recognisable cases. It lowers
/// the risk; it cannot recognise a one-time link that carries no hint of being one.
public enum LinkPreviewPolicy {
    private static let localSuffixes = [".local", ".internal", ".lan", ".home", ".localdomain"]

    /// Path words that suggest the link performs an action or belongs to an account flow.
    /// Matched as whole words, so "/authors/" is not mistaken for "auth".
    private static let actionWords = [
        "unsubscribe", "confirm", "verify", "activate", "reset", "magic", "login", "logout", "signin",
        "signout", "auth", "oauth", "token", "invite", "delete", "remove", "cancel", "approve",
        "accept", "decline", "callback", "authenticate", "authorize", "authorization", "verification",
        "confirmation", "activation",
    ]

    /// Query parameter names that suggest the link carries a credential.
    private static let secretWords = [
        "token", "code", "key", "secret", "signature", "sig", "auth", "password", "otp", "session",
        "ticket", "nonce",
    ]

    /// - Parameter allowLocalHosts: relaxes only the host and port rules; for testing against a
    ///   server on this machine.
    public static func shouldFetch(_ url: URL, allowLocalHosts: Bool = false) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil
        else { return false }

        if !allowLocalHosts {
            guard isPublicHostName(host) else { return false }
            if let port = components.port, port != 80, port != 443 { return false }
        }

        let pathWords = words(in: components.path.lowercased())
        guard !pathWords.contains(where: actionWords.contains) else { return false }

        let parameterNames = (components.queryItems ?? []).map { $0.name.lowercased() }
        return !parameterNames.contains { words(in: $0).contains(where: secretWords.contains) }
    }

    /// A dotted name that is neither an IP address nor a local-network name.
    private static func isPublicHostName(_ host: String) -> Bool {
        guard host != "localhost", host.contains("."), !host.contains(":") else { return false }
        guard !localSuffixes.contains(where: host.hasSuffix) else { return false }
        // All-numeric labels mean an IPv4 address.
        return !host.split(separator: ".").allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    /// Splits on anything that is not a letter or digit: "reset-password" → ["reset", "password"].
    private static func words(in string: String) -> [String] {
        string.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// How the app names itself to the sites it fetches previews from.
    public static func userAgent(appVersion: String?) -> String {
        "Mozilla/5.0 (Macintosh) AraNotch" + (appVersion.map { "/\($0)" } ?? "") + " link-preview"
    }
}
