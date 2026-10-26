import AgentCore
import Foundation
import Testing
@testable import AgentFeature

@Suite @MainActor struct CodexWatcherTests {
    @Test func aLongLogIsReadQuicklyAtLaunch() throws {
        // The newest Codex log on this Mac was 14 MB in 171 lines, most of them conversation
        // content; reading it at launch held the main thread for about two thirds of a second.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var text = #"{"timestamp":"2026-10-07T01:15:31.250Z","type":"session_meta","payload":{"id":"s-1","cwd":"/Users/a/app"}}"# + "\n"
        let content = String(repeating: "lorem ipsum dolor sit amet ", count: 3_000)
        for index in 0..<180 {
            text += #"{"timestamp":"2026-10-07T01:16:00.000Z","type":"response_item","payload":{"type":"message","n":\#(index),"text":"\#(content)"}}"# + "\n"
        }
        text += #"{"timestamp":"2026-10-07T02:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12,"resets_at":1791400000},"secondary":{"used_percent":30}}}}"# + "\n"
        try Data(text.utf8).write(to: directory.appendingPathComponent("rollout-2026-10-07T01-15-31-s-1.jsonl"))
        #expect(text.utf8.count > 14_000_000)

        let watcher = CodexWatcher(directory: directory)
        var events: [CodexRolloutEvent] = []
        watcher.onEvents = { events += $0.map(\.event) }
        let started = Date()
        watcher.start()
        let took = Date().timeIntervalSince(started)
        watcher.stop()

        #expect(events.count == 2)
        if case .session(let id, _, _) = events.first {} else { Issue.record("no session read") }
        if case .usage = events.last {} else { Issue.record("no usage read") }
        // Over a second before, in a test build; about a tenth of that now, less in the app.
        #expect(took < 0.4, "reading took \(took) s")
    }
}
