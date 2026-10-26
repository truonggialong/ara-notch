import Foundation
import Testing
@testable import ClipboardCore

@Suite struct BackupExclusionTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func isExcluded(_ url: URL) throws -> Bool {
        try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup ?? false
    }

    @Test func theHistoryFolderIsLeftOutOfBackupsAndCanBePutBack() throws {
        let url = try folder()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try !isExcluded(url))
        try BackupExclusion.apply(true, to: url)
        #expect(try isExcluded(url))
        try BackupExclusion.apply(false, to: url)
        #expect(try !isExcluded(url))
    }

    @Test func historyIsLeftOutOfBackupsUnlessTheUserSaysOtherwise() {
        let defaults = InMemoryDefaults()
        let store = ClipboardSettingsStore(defaults: defaults)
        #expect(store.excludedFromBackup)
        store.excludedFromBackup = false
        #expect(!ClipboardSettingsStore(defaults: defaults).excludedFromBackup)
    }
}
