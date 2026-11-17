import AgentCore
import Foundation

/// Asks Claude Code for Claude's limits, as `/usage` does: starts it bare (`ClaudeCodeUsage.arguments`),
/// sends `initialize` and `get_usage`, reads its reply and stops it. Claude Code reads its own
/// sign-in, so this app touches no keychain item. Blocking: call it off the main thread.
enum ClaudeCodeUsageProbe {
    enum Outcome: Equatable, Sendable {
        case usage(AgentUsage)
        /// Claude Code answered without numbers.
        case empty
        /// Claude Code is not on this Mac.
        case missing
        /// It did not start, or did not answer in time.
        case failed
    }

    /// Where Claude Code's installers put it; the app does not inherit a shell's PATH.
    static func executable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let places = [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return places.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func ask(timeout: TimeInterval = 20) -> Outcome {
        guard let executable = executable() else { return .missing }
        let process = Process()
        process.executableURL = executable
        process.arguments = ClaudeCodeUsage.arguments
        process.environment = ClaudeCodeUsage.environment(ProcessInfo.processInfo.environment)
        // An empty folder of its own, so no project settings or instructions are picked up.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let answer = Answer()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            answer.take(data, ended: data.isEmpty)
        }
        do { try process.run() } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return .failed
        }
        let lines = ClaudeCodeUsage.requests.map { $0 + "\n" }.joined()
        try? input.fileHandleForWriting.write(contentsOf: Data(lines.utf8))

        let reply = answer.wait(timeout: timeout)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { usleep(50_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }

        switch reply {
        case .usage(let usage): return .usage(usage)
        case .empty: return .empty
        case nil: return .failed
        }
    }

    /// Gathers Claude Code's output line by line until the reply to `get_usage` comes.
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var buffer = Data()
        private var reply: ClaudeCodeUsage.Reply?
        private var finished = false

        func take(_ data: Data, ended: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            buffer.append(data)
            while let end = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<end]
                buffer.removeSubrange(buffer.startIndex...end)
                if let found = ClaudeCodeUsage.reply(fromLine: Data(line), at: Date()) {
                    reply = found
                    finish()
                    return
                }
            }
            // Keeps no more than a megabyte of a line that never ends.
            if buffer.count > 1 << 20 { buffer.removeAll() }
            if ended { finish() }
        }

        private func finish() {
            finished = true
            done.signal()
        }

        func wait(timeout: TimeInterval) -> ClaudeCodeUsage.Reply? {
            _ = done.wait(timeout: .now() + timeout)
            lock.lock()
            defer { lock.unlock() }
            finished = true
            return reply
        }
    }
}
