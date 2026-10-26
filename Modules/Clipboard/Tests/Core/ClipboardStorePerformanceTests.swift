import Foundation
import Testing
@testable import ClipboardCore

/// The app reads the whole history again after every copy, so reading must stay quick even
/// with the largest history the settings allow.
@Suite struct ClipboardStorePerformanceTests {
    private func timed(_ body: () throws -> Void) rethrows -> TimeInterval {
        let start = Date()
        try body()
        return Date().timeIntervalSince(start)
    }

    private func makeStore(clips: Int, bytesEach: Int) throws -> (ClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aranotch-perf-\(UUID().uuidString)", isDirectory: true)
        let store = try ClipboardStore(directory: directory, maxItems: 1000)
        let filler = String(repeating: "con cáo nâu nhanh nhẹn ", count: max(1, bytesEach / 30))
        let source = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
        for index in 0..<clips {
            try store.add(.text("\(index) \(filler)"), source: source, at: Date(timeIntervalSince1970: Double(index)))
        }
        return (store, directory)
    }

    @Test func readingAThousandOrdinaryClipsIsQuick() throws {
        let (store, directory) = try makeStore(clips: 1000, bytesEach: 2000)
        defer { try? FileManager.default.removeItem(at: directory) }
        var count = 0
        let seconds = try timed { count = try store.items().count }
        print("perf: read \(count) clips of 2 KB in \(String(format: "%.1f", seconds * 1000)) ms")
        #expect(count == 1000)
        #expect(seconds < 0.25)
    }

    @Test func aCopyIntoAFullHistoryIsQuick() throws {
        let (store, directory) = try makeStore(clips: 1000, bytesEach: 2000)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
        let seconds = try timed {
            try store.add(.text("mới chép"), source: source, at: Date(timeIntervalSince1970: 5000))
            _ = try store.items()
        }
        print("perf: copy into a full history, then read it, in \(String(format: "%.1f", seconds * 1000)) ms")
        #expect(seconds < 0.3)
    }

    @Test func searchingAThousandClipsIsQuick() throws {
        let (store, directory) = try makeStore(clips: 1000, bytesEach: 2000)
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = try store.items()
        var found = 0
        let seconds = timed { found = items.filter { ClipQuery("999 con cao").matches($0) }.count }
        print("perf: searched \(items.count) clips in \(String(format: "%.1f", seconds * 1000)) ms, found \(found)")
        #expect(found == 1)
        #expect(seconds < 0.3)
    }

    @Test func aHistoryOfVeryLargeClipsIsStillReadable() throws {
        // 200 clips of 200 KB: 40 MB of text, far more than ordinary use.
        let (store, directory) = try makeStore(clips: 200, bytesEach: 200_000)
        defer { try? FileManager.default.removeItem(at: directory) }
        var count = 0
        let seconds = try timed { count = try store.items().count }
        print("perf: read \(count) clips of 200 KB in \(String(format: "%.1f", seconds * 1000)) ms")
        #expect(count == 200)
        #expect(seconds < 1.5)
    }
}
