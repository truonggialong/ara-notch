import AgentCore
import Foundation

/// What the agent list learns from outside the hook events, off the main thread.
enum ClaudeSessionProbe {
    /// The sessions open in a running Claude Code; nil when the process list could not be read.
    static func runningSessionIDs() -> Set<String>? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "command="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let commands = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        return RunningClaudeSessions.ids(fromCommands: commands)
    }

    /// Whether the session's transcript ends with the user stopping the turn. Only the last
    /// 16 KB of `~/.claude/projects/<folder>/<session>.jsonl` are read.
    static func wasInterrupted(sessionID: String, projects: URL) -> Bool {
        guard let transcript = transcript(of: sessionID, in: projects),
              let handle = try? FileHandle(forReadingFrom: transcript)
        else { return false }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let tail: UInt64 = 16 * 1024
        try? handle.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? handle.readToEnd() else { return false }
        var lines = String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
        // The first line read may be cut; it is not looked at.
        if size > tail, !lines.isEmpty { lines.removeFirst() }
        return TranscriptEnding.wasInterrupted(lastLines: lines)
    }

    private static func transcript(of sessionID: String, in projects: URL) -> URL? {
        // A session id is letters, digits and dashes; anything else never becomes a path.
        guard !sessionID.isEmpty, sessionID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              let folders = try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil) else {
            return nil
        }
        return folders.lazy
            .map { $0.appendingPathComponent("\(sessionID).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
