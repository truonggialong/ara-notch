import Foundation
import Testing
@testable import AgentCore

@Suite struct AgentHeadlineTests {
    @Test func waitingForTheUserComesFirstWithItsCount() {
        let states: [AgentSession.State] = [.working(tool: nil), .waiting(message: nil), .done, .waiting(message: "Bash")]
        #expect(AgentHeadline(states) == AgentHeadline(kind: .waiting, count: 2))
    }

    @Test func thenWorkingThenDoneThenJustOpened() {
        #expect(AgentHeadline([.done, .working(tool: "Edit"), .working(tool: nil)]) == AgentHeadline(kind: .working, count: 2))
        #expect(AgentHeadline([.idle, .done]) == AgentHeadline(kind: .done, count: 1))
        #expect(AgentHeadline([.idle]) == AgentHeadline(kind: .idle, count: 1))
    }

    @Test func noSessionsHaveNoHeadline() {
        #expect(AgentHeadline([]) == nil)
    }
}
