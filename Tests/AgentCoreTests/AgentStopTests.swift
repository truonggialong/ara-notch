import Foundation
import Testing
@testable import AgentCore

private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func event(_ kind: AgentEvent.Kind, _ id: String, at seconds: TimeInterval) -> AgentEvent {
    AgentEvent(kind: kind, sessionID: id, cwd: "/Users/me/web", toolName: nil, message: nil, at: date(seconds))
}

private func line(_ type: String, _ text: String) -> String {
    let object: [String: Any] = ["type": type, "message": ["role": type, "content": [["type": "text", "text": text]]]]
    return String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

@Suite struct TranscriptEndingTests {
    @Test func aTurnTheUserStoppedEndsWithTheInterruptLine() {
        let lines = [line("user", "làm tiếp"), line("assistant", "Đang sửa…"),
                     line("user", "[Request interrupted by user]"), #"{"type":"file-history-snapshot"}"#]
        #expect(TranscriptEnding.wasInterrupted(lastLines: lines))
    }

    @Test func aStopWhileAToolRanCountsToo() {
        #expect(TranscriptEnding.wasInterrupted(lastLines: [line("user", "[Request interrupted by user for tool use]")]))
    }

    @Test func aTurnThatGoesOnIsNotStopped() {
        #expect(!TranscriptEnding.wasInterrupted(lastLines: [line("user", "[Request interrupted by user]"), line("assistant", "Tiếp tục")]))
        #expect(!TranscriptEnding.wasInterrupted(lastLines: [line("user", "sửa giúp tôi")]))
        #expect(!TranscriptEnding.wasInterrupted(lastLines: ["not json", ""]))
    }
}

@Suite struct StoppedSessionTests {
    @Test func aWorkingSessionCanBeMarkedStopped() {
        var sessions = AgentSessions()
        sessions.apply(event(.promptSubmit, "a", at: 10))
        sessions.markStopped(id: "a")
        #expect(sessions.session(id: "a")?.state == .stopped)
        // A new request sets it to work again.
        sessions.apply(event(.promptSubmit, "a", at: 20))
        #expect(sessions.session(id: "a")?.state == .working(tool: nil))
    }

    @Test func onlyAWorkingOrWaitingSessionIsStopped() {
        var sessions = AgentSessions()
        sessions.apply(event(.stop, "done", at: 10))
        sessions.markStopped(id: "done")
        #expect(sessions.session(id: "done")?.state == .done)
    }

    @Test func aTurnQuietForTooLongCountsAsStopped() {
        var sessions = AgentSessions()
        sessions.apply(event(.promptSubmit, "quiet", at: 0))
        sessions.apply(event(.promptSubmit, "busy", at: 1_700))
        sessions.stopTurns(quietSince: date(1_000))
        #expect(sessions.session(id: "quiet")?.state == .stopped)
        #expect(sessions.session(id: "busy")?.state == .working(tool: nil))
    }

    @Test func aSessionStillRunningIsKeptPastItsLifetime() {
        var sessions = AgentSessions()
        sessions.apply(event(.sessionStart, "open", at: 0))
        sessions.apply(event(.sessionStart, "gone", at: 0))
        sessions.expire(before: date(100), keeping: ["open"])
        #expect(sessions.list.map(\.id) == ["open"])
    }

    @Test func aStoppedSessionReadsAsDoneInTheHeadline() {
        #expect(AgentHeadline([.stopped, .idle]) == AgentHeadline(kind: .done, count: 1))
    }
}

@Suite struct RunningClaudeSessionTests {
    @Test func readsTheSessionsTheRunningClaudeProcessesResume() {
        let commands = [
            "/Users/me/Library/Application Support/Claude/claude-code/2.1/claude.app/Contents/MacOS/claude --output-format stream-json --resume=08e663e6-574d-41db-9604-e6afabdeefc0 --model=opus",
            "/Users/me/.local/bin/claude --resume 3dedd686-04f5-4690-9d86-2e06b5b61f75",
            "claude --session-id 65bf5563-d40f-456c-b4ff-28c6817a7e51",
            "/usr/bin/vim --resume=not-a-session-id",
            "zsh",
        ]
        #expect(RunningClaudeSessions.ids(fromCommands: commands) == [
            "08e663e6-574d-41db-9604-e6afabdeefc0", "3dedd686-04f5-4690-9d86-2e06b5b61f75", "65bf5563-d40f-456c-b4ff-28c6817a7e51",
        ])
    }
}
