import AgentCore
import Foundation

/// Installs this app's hooks into Claude Code's settings file and removes them again.
/// The settings file is backed up before every change and written atomically.
@MainActor
final class ClaudeHooks {
    enum Problem: Error, Equatable {
        /// The settings file exists but is not a JSON object; it is left untouched.
        case unreadableSettings
        /// The helper program is missing from the app.
        case helperMissing
        /// The user already has a status line of their own.
        case foreignStatusLine
        case cannotWrite(String)
    }

    let settingsFile: URL
    /// Where the helper is copied to, so the hook keeps working when the app moves or is rebuilt.
    let helperDestination: URL
    private let bundledHelper: URL

    init(settingsFile: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.settingsFile = settingsFile ?? home.appendingPathComponent(".claude/settings.json")
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support")
        helperDestination = support.appendingPathComponent("AraNotch/bin/aranotch-hook")
        bundledHelper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/aranotch-hook")
    }

    var isInstalled: Bool {
        (try? readSettings()).map(ClaudeHooksInstaller.isInstalled(in:)) ?? false
    }

    /// Copies the helper into place, backs the settings up and adds the hooks.
    /// - Returns: the backup that was made, or nil when there was no settings file yet.
    @discardableResult
    func install() throws -> URL? {
        try copyHelper()
        let settings = try readSettings()
        let command = ClaudeHooksInstaller.command(forHelperAt: helperDestination.path)
        return try write(ClaudeHooksInstaller.install(into: settings, command: command))
    }

    /// Backs the settings up and takes the hooks out. The helper copy is left in place: a
    /// session started earlier may still call it.
    @discardableResult
    func uninstall() throws -> URL? {
        let settings = try readSettings()
        guard ClaudeHooksInstaller.isInstalled(in: settings) else { return nil }
        return try write(ClaudeHooksInstaller.uninstall(from: settings))
    }

    /// Takes out the hooks and the status line together, in one change with one backup.
    @discardableResult
    func uninstallAll() throws -> URL? {
        var settings = try readSettings()
        let hadHooks = ClaudeHooksInstaller.isInstalled(in: settings)
        let hadStatusLine = ClaudeStatusLineInstaller.state(of: settings) == .installed
        guard hadHooks || hadStatusLine else { return nil }
        if hadHooks {
            settings = ClaudeHooksInstaller.uninstall(from: settings)
        }
        if hadStatusLine {
            settings = ClaudeStatusLineInstaller.uninstall(from: settings)
        }
        return try write(settings)
    }

    /// Refreshes the helper copy when the app carries a different one (after an update).
    func refreshHelperIfInstalled() {
        guard isInstalled || statusLineState == .installed else { return }
        try? copyHelper()
    }

    // MARK: - Status line

    var statusLineState: ClaudeStatusLineInstaller.State {
        (try? readSettings()).map(ClaudeStatusLineInstaller.state(of:)) ?? .absent
    }

    /// Copies the helper into place, backs the settings up and sets the status line command.
    /// - Returns: the backup that was made; throws `.foreignStatusLine` when the user has a
    ///   status line of their own, which is never replaced.
    @discardableResult
    func installStatusLine() throws -> URL? {
        try copyHelper()
        let settings = try readSettings()
        let command = ClaudeStatusLineInstaller.command(forHelperAt: helperDestination.path)
        guard let changed = ClaudeStatusLineInstaller.install(into: settings, command: command) else {
            throw Problem.foreignStatusLine
        }
        return try write(changed)
    }

    @discardableResult
    func uninstallStatusLine() throws -> URL? {
        let settings = try readSettings()
        guard ClaudeStatusLineInstaller.state(of: settings) == .installed else { return nil }
        return try write(ClaudeStatusLineInstaller.uninstall(from: settings))
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsFile.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Problem.unreadableSettings }
        return object
    }

    private func write(_ settings: [String: Any]) throws -> URL? {
        let manager = FileManager.default
        var backup: URL?
        do {
            if manager.fileExists(atPath: settingsFile.path) {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                // Named to the second, and numbered when a second change comes in the same second.
                let base = "settings.json.aranotch-backup-\(formatter.string(from: Date()))"
                var copy = settingsFile.deletingLastPathComponent().appendingPathComponent(base)
                var number = 2
                while manager.fileExists(atPath: copy.path) {
                    copy = settingsFile.deletingLastPathComponent().appendingPathComponent("\(base)-\(number)")
                    number += 1
                }
                try manager.copyItem(at: settingsFile, to: copy)
                backup = copy
            } else {
                try manager.createDirectory(at: settingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: settingsFile, options: .atomic)
        } catch {
            throw Problem.cannotWrite(error.localizedDescription)
        }
        return backup
    }

    private func copyHelper() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: bundledHelper.path) else { throw Problem.helperMissing }
        if manager.contentsEqual(atPath: bundledHelper.path, andPath: helperDestination.path) { return }
        do {
            try manager.createDirectory(at: helperDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Copy beside the target, then swap, so a running agent never finds half a file.
            let staged = helperDestination.deletingLastPathComponent().appendingPathComponent(".aranotch-hook.new")
            try? manager.removeItem(at: staged)
            try manager.copyItem(at: bundledHelper, to: staged)
            _ = try manager.replaceItemAt(helperDestination, withItemAt: staged)
        } catch {
            throw Problem.cannotWrite(error.localizedDescription)
        }
    }
}
