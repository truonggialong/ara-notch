import Foundation
import Testing
@testable import ClipboardCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
private let day: TimeInterval = 86_400

private func withStore(_ body: (ClipboardStore, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("aranotch-retention-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(try ClipboardStore(directory: directory, inMemory: true), directory)
}

private let source = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")

@Suite struct ClipRetentionTests {
    @Test func neverHasNoCutoff() {
        #expect(ClipRetention.never.cutoff(from: date(1_000_000)) == nil)
    }

    @Test(arguments: [
        (ClipRetention.day, 1.0), (.week, 7.0), (.month, 30.0), (.year, 365.0),
    ])
    func cutoffIsThatManyDaysBack(retention: ClipRetention, days: Double) {
        let now = date(100_000_000)
        #expect(retention.cutoff(from: now) == now.addingTimeInterval(-days * day))
    }

    @Test func rawValuesAreStable() {
        #expect(ClipRetention.allCases.map(\.rawValue) == ["never", "day", "week", "month", "year"])
    }
}

@Suite struct ClipboardStoreExpiryTests {
    @Test func deletesUnpinnedClipsLastUsedBeforeTheCutoff() throws {
        try withStore { store, _ in
            try store.add(.text("cũ"), source: source, at: date(100))
            try store.add(.text("mới"), source: source, at: date(300))
            let removed = try store.deleteUnpinned(olderThan: date(200))
            #expect(removed == 1)
            try #expect(store.items().map(\.text) == ["mới"])
        }
    }

    @Test func aClipUsedAgainRecentlyIsKept() throws {
        try withStore { store, _ in
            let old = try #require(try store.add(.text("cũ"), source: source, at: date(100)))
            try store.touch(id: old.id, at: date(500))
            try #expect(store.deleteUnpinned(olderThan: date(200)) == 0)
            try #expect(store.items().count == 1)
        }
    }

    @Test func clipExactlyAtTheCutoffIsKept() throws {
        try withStore { store, _ in
            try store.add(.text("đúng mốc"), source: source, at: date(200))
            try #expect(store.deleteUnpinned(olderThan: date(200)) == 0)
        }
    }

    @Test func pinnedClipsAreNeverExpired() throws {
        try withStore { store, _ in
            let board = try store.createBoard(name: "Việc", symbolName: "pin", at: date(1))
            let pinned = try #require(try store.add(.text("ghim"), source: source, at: date(100)))
            try store.pin(itemID: pinned.id, toBoard: board.id, at: date(101))
            try store.add(.text("thường"), source: source, at: date(100))
            try #expect(store.deleteUnpinned(olderThan: date(900)) == 1)
            try #expect(store.items().map(\.text) == ["ghim"])
        }
    }

    @Test func expiredImagesLoseTheirFiles() throws {
        try withStore { store, directory in
            try store.add(.image(Data([1, 2, 3])), source: source, at: date(100))
            _ = try store.deleteUnpinned(olderThan: date(200))
            let files = (try? FileManager.default.contentsOfDirectory(
                atPath: directory.appendingPathComponent("blobs").path)) ?? []
            #expect(files.isEmpty)
        }
    }

    @Test func nothingToExpireRemovesNothing() throws {
        try withStore { store, _ in
            try #expect(store.deleteUnpinned(olderThan: date(200)) == 0)
        }
    }
}
