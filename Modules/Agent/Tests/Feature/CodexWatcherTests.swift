import AgentCore
import Foundation
import Testing
@testable import AgentFeature

@Suite @MainActor struct CodexWatcherTests {
    private static let session = #"{"timestamp":"2026-10-07T01:15:31.250Z","type":"session_meta","payload":{"id":"s-1","cwd":"/Users/a/app"}}"#
    private static let usage = #"{"timestamp":"2026-10-07T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12,"resets_at":1791400000},"secondary":{"used_percent":30}}}}"#

    private func folder() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Waits on the main actor until `done` holds, at most `seconds`.
    private func wait(_ seconds: Double, until done: () -> Bool) async {
        let end = Date().addingTimeInterval(seconds)
        while !done(), Date() < end {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test func aLongLogIsReadOffTheMainThreadAsHistory() async throws {
        // The newest Codex log on this Mac was 14 MB in 171 lines, most of them conversation
        // content; reading it at launch held the main thread for about two thirds of a second.
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var text = Self.session + "\n"
        let content = String(repeating: "lorem ipsum dolor sit amet ", count: 3_000)
        for index in 0..<180 {
            text += #"{"timestamp":"2026-10-07T01:16:00.000Z","type":"response_item","payload":{"type":"message","n":\#(index),"text":"\#(content)"}}"# + "\n"
        }
        text += Self.usage + "\n"
        try Data(text.utf8).write(to: directory.appendingPathComponent("rollout-2026-10-07T01-15-31-s-1.jsonl"))
        #expect(text.utf8.count > 14_000_000)

        let watcher = CodexWatcher(directory: directory)
        var events: [CodexRolloutEvent] = []
        var histories: [Bool] = []
        watcher.onEvents = { found, isHistory in
            events += found.map(\.event)
            histories.append(isHistory)
        }
        let started = Date()
        watcher.start()
        let took = Date().timeIntervalSince(started)
        await wait(10) { events.count >= 2 }
        watcher.stop()

        // Starting no longer reads: the main thread is free at once.
        #expect(took < 0.05, "starting took \(took) s")
        #expect(events.count == 2)
        if case .session = events.first {} else { Issue.record("no session read") }
        if case .usage = events.last {} else { Issue.record("no usage read") }
        #expect(histories.allSatisfy { $0 })
    }

    @Test func aLogCodexKeepsOpenIsReadAsItGrows() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("rollout-2026-10-07T01-15-31-s-1.jsonl")
        try Data((Self.session + "\n").utf8).write(to: log)

        let watcher = CodexWatcher(directory: directory)
        var live: [CodexRolloutEvent] = []
        var history: [CodexRolloutEvent] = []
        watcher.onEvents = { found, isHistory in
            if isHistory { history += found.map(\.event) } else { live += found.map(\.event) }
        }
        watcher.start()
        await wait(5) { !history.isEmpty }

        // Written and left open, as Codex does: no close for the system to report.
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Self.usage + "\n").utf8))
        await wait(6) { !live.isEmpty }
        try handle.close()
        watcher.stop()

        #expect(history.count == 1)
        if case .usage = live.first {} else { Issue.record("the growing log was not read") }
    }
}
