import Foundation
import Testing
@testable import ClipboardCore

private let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
private let moment = Date(timeIntervalSince1970: 1_791_900_000)

/// Runs the body with a fresh temporary directory and removes it afterwards.
private func withDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-recovery-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

/// A history on disk with one clip in it, closed again.
private func makeHistory(in directory: URL) throws {
    let store = try ClipboardStore(directory: directory)
    try store.add(.text("kept"), source: notes, at: moment)
}

private func file(in directory: URL) -> URL {
    directory.appendingPathComponent("clipboard.sqlite")
}

/// Overwrites part of the file, as a crash in the middle of a write or a failing disk would.
private func damage(_ url: URL, from start: Int, to end: Int) throws {
    var bytes = try Data(contentsOf: url)
    for index in start..<min(end, bytes.count) { bytes[index] = 0x5A }
    try bytes.write(to: url)
}

private func setAsideFiles(in directory: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
        .filter { $0.hasPrefix("clipboard-damaged-") }
}

@Suite struct ClipboardStoreRecoveryTests {
    @Test func aHealthyHistoryOpensAsItIs() throws {
        try withDirectory { directory in
            try makeHistory(in: directory)
            let opened = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)
            #expect(opened.setAside == nil)
            #expect(try opened.store.items().map(\.text) == ["kept"])
            #expect(setAsideFiles(in: directory).isEmpty)
        }
    }

    @Test func aDamagedHistoryIsSetAsideAndAFreshOneTakesItsPlace() throws {
        try withDirectory { directory in
            try makeHistory(in: directory)
            try damage(file(in: directory), from: 100, to: 8192)
            let damagedBytes = try Data(contentsOf: file(in: directory))

            let opened = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)

            // The damaged file is kept, untouched, under a name that says what it is and when.
            let aside = try #require(opened.setAside)
            #expect(aside.lastPathComponent.hasPrefix("clipboard-damaged-"))
            #expect(aside.pathExtension == "sqlite")
            #expect(try Data(contentsOf: aside) == damagedBytes)
            // The new history is empty and works: what is copied next is kept.
            #expect(try opened.store.items().isEmpty)
            try opened.store.add(.text("after"), source: notes, at: moment)
            #expect(try opened.store.items().map(\.text) == ["after"])
        }
    }

    @Test func damageDeepInTheFileIsFoundAtOpening() throws {
        // Not only a broken header: a page further in, which plain opening does not read.
        try withDirectory { directory in
            let store = try ClipboardStore(directory: directory)
            for index in 0..<200 {
                try store.add(.text("clip \(index) " + String(repeating: "x", count: 400)), source: notes, at: moment)
            }
            let size = try Data(contentsOf: file(in: directory)).count
            #expect(size > 40_000)
            try damage(file(in: directory), from: size - 12_000, to: size - 4_000)

            let opened = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)
            #expect(opened.setAside != nil)
        }
    }

    @Test func aFileThatIsNoDatabaseAtAllIsSetAside() throws {
        try withDirectory { directory in
            try Data("not a database".utf8).write(to: file(in: directory))
            let opened = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)
            #expect(opened.setAside != nil)
            #expect(try opened.store.items().isEmpty)
        }
    }

    @Test func aHistoryFromANewerVersionIsLeftAlone() throws {
        // Not damage: an older copy of the app must not move away what a newer one wrote.
        try withDirectory { directory in
            try makeHistory(in: directory)
            let database = try SQLiteDatabase(path: file(in: directory).path)
            try database.setUserVersion(ClipboardStore.schemaVersion + 1)
            let before = try Data(contentsOf: file(in: directory))

            #expect(throws: ClipboardStoreError.unsupportedSchema(version: ClipboardStore.schemaVersion + 1)) {
                _ = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)
            }
            #expect(setAsideFiles(in: directory).isEmpty)
            #expect(try Data(contentsOf: file(in: directory)) == before)
        }
    }

    @Test func twoRecoveriesKeepBothDamagedFiles() throws {
        try withDirectory { directory in
            try Data("broken once".utf8).write(to: file(in: directory))
            _ = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)
            try Data("broken twice".utf8).write(to: file(in: directory))
            _ = try ClipboardStore.openRecovering(directory: directory, maxItems: 500, at: moment)
            #expect(setAsideFiles(in: directory).count == 2)
        }
    }
}
