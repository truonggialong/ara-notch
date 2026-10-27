import AgentCore
import Foundation
import Testing
@testable import AgentFeature

@Suite struct ClaudeAccountReaderTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)

    static func state(_ exitStatus: Int32, _ output: String = "") -> ClaudeAccountReader.State? {
        if case .failure(let error) = ClaudeAccountReader.login(exitStatus: exitStatus, output: Data(output.utf8), now: now) {
            return error.state
        }
        return nil
    }

    @Test func readsTheLoginThatSecurityPrints() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"t-1","expiresAt":2000000000}}"# + "\n"
        let result = ClaudeAccountReader.login(exitStatus: 0, output: Data(json.utf8), now: Self.now)
        #expect(try result.get() == .valid(accessToken: "t-1"))
    }

    @Test func mapsSecurityExitStatuses() {
        #expect(Self.state(0, "not json") == .noLogin)
        #expect(Self.state(44) == .noLogin)
        #expect(Self.state(128) == .refused)
        #expect(Self.state(51) == .refused)
        #expect(Self.state(36) == .refused)
        #expect(Self.state(1) == .failed(status: 1))
    }
}
