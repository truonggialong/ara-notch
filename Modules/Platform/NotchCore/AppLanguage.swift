import Foundation

/// The language the app speaks: the Mac's, or one chosen for this app alone. It is kept the
/// way macOS keeps a language chosen for an app in System Settings, as the app's own
/// `AppleLanguages`, and takes effect the next time the app opens.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case vietnamese = "vi"
    case english = "en"

    static let key = "AppleLanguages"

    /// - Parameter domain: the app's own settings, without the Mac's: a language there was
    ///   chosen for this app.
    public static func read(fromAppDomain domain: [String: Any]?) -> AppLanguage {
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        let code = first.split(separator: "-").first.map(String.init) ?? first
        return AppLanguage(rawValue: code).flatMap { $0 == .system ? nil : $0 } ?? .system
    }

    public func write(to defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set([rawValue], forKey: Self.key)
        }
    }

    /// The arguments to open the app with again after the language changed: the ones it was
    /// opened with, and Settings open on General, where the choice was made.
    public static func relaunchArguments(from arguments: [String]) -> [String] {
        var kept: [String] = []
        var rest = arguments.dropFirst()[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--show-settings":
                continue
            case "--settings-tab":
                _ = rest.popFirst()
            default:
                kept.append(argument)
            }
        }
        return kept + ["--show-settings", "--settings-tab", "general"]
    }
}
