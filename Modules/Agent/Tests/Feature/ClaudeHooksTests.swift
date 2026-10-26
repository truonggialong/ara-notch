import AgentCore
import Foundation
import Testing
@testable import AgentFeature

@Suite @MainActor struct ClaudeHooksTests {
    /// A Claude Code settings file with this app's hooks and status line in it, and a setting
    /// of the user's own.
    private func settingsFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let helper = "/Users/someone/Library/Application Support/AraNotch/bin/aranotch-hook"
        var settings: [String: Any] = ["theme": "dark"]
        settings = ClaudeHooksInstaller.install(into: settings, command: ClaudeHooksInstaller.command(forHelperAt: helper))
        settings = try #require(ClaudeStatusLineInstaller.install(
            into: settings, command: ClaudeStatusLineInstaller.command(forHelperAt: helper)))
        let file = folder.appendingPathComponent("settings.json")
        try JSONSerialization.data(withJSONObject: settings).write(to: file)
        return file
    }

    private func read(_ file: URL) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    }

    @Test func removingAraNotchTakesOutTheHooksAndTheStatusLineAtOnce() throws {
        let file = try settingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try ClaudeHooks(settingsFile: file).uninstallAll()
        let settings = try read(file)
        #expect(!ClaudeHooksInstaller.isInstalled(in: settings))
        #expect(ClaudeStatusLineInstaller.state(of: settings) == .absent)
        #expect(settings["theme"] as? String == "dark")
    }

    @Test func twoChangesInTheSameSecondEachKeepABackup() throws {
        // The backups were named to the second: the second change in a second failed.
        let file = try settingsFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let hooks = ClaudeHooks(settingsFile: file)
        try hooks.uninstall()
        try hooks.uninstallStatusLine()
        let backups = try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path)
            .filter { $0.hasPrefix("settings.json.aranotch-backup-") }
        #expect(backups.count == 2)
        #expect(ClaudeStatusLineInstaller.state(of: try read(file)) == .absent)
    }
}
