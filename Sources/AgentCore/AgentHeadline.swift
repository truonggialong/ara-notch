import Foundation

/// What a small tile says about the agents in one line: the most pressing state any session is
/// in, and how many sessions are in it. Waiting for the user comes first, then working, then
/// done, then just opened.
public struct AgentHeadline: Equatable, Sendable {
    public enum Kind: Int, Equatable, Sendable {
        case waiting, working, done, idle
    }

    public let kind: Kind
    public let count: Int

    public init(kind: Kind, count: Int) {
        self.kind = kind
        self.count = count
    }

    public init?(_ states: [AgentSession.State]) {
        let kinds = states.map(Self.kind(of:))
        guard let first = kinds.min(by: { $0.rawValue < $1.rawValue }) else { return nil }
        self.init(kind: first, count: kinds.filter { $0 == first }.count)
    }

    private static func kind(of state: AgentSession.State) -> Kind {
        switch state {
        case .waiting: .waiting
        case .working: .working
        case .done, .stopped: .done
        case .idle: .idle
        }
    }
}
