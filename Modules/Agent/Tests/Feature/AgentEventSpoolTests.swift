import Foundation
import Testing
@testable import AgentFeature

private func line(_ index: Int) -> String {
    #"{"cwd":"/Users/demo/project","event":"PreToolUse","session":"s1","t":\#(1_791_000_000 + index).5,"tool":"Bash"}"# + "\n"
}

@Suite @MainActor struct AgentEventSpoolTests {
    @Test func aFileThatGrowsWhileTheAppRunsIsCutDownToItsNewestLines() throws {
        // The hook appends a line for every tool an agent uses; with the app running for days
        // the file used to grow until the next launch.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("spool-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(line(0).utf8).write(to: file)
        let spool = AgentEventSpool(file: file)
        var received = 0
        spool.onEvents = { received += $0.count }
        spool.readNew()
        #expect(received == 1)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        var text = ""
        for index in 1...12_000 { text += line(index) }
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        #expect(try Data(contentsOf: file).count > 1_000_000)

        spool.readNew()
        // Every event was handed over before the cut, and the file is small again.
        #expect(received == 12_001)
        #expect(try Data(contentsOf: file).count < 200_000)

        // What the hook appends after the cut is still read, once.
        let after = try FileHandle(forWritingTo: file)
        try after.seekToEnd()
        try after.write(contentsOf: Data(line(12_001).utf8))
        try after.close()
        spool.readNew()
        #expect(received == 12_002)
    }
}
