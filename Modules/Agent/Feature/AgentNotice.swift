import AgentCore
import NotchShell
import SwiftUI

/// What a notice about an agent says, on the sign the notch grows into for a few seconds:
/// which agent and where, what it is at, and what the turn means for its five-hour limit.
struct AgentNotice: Equatable {
    enum Kind: Equatable {
        /// The agent set to work on a request.
        case working
        /// The agent asks for the user; with what it said, when it said anything.
        case attention(message: String?)
        /// The turn is done; with what it took from the limit, when that could be measured.
        case finished(costPercent: Double?)
    }

    var kind: Kind
    /// "Claude" or "Codex".
    var agent: String
    var project: String
    /// The agent's limit as it stands; nil when the agent never reported one.
    var forecast: UsageForecast?
    var now: Date

    /// The sign: the agent and its project on the left with what it is at, the numbers of
    /// its limit (or what it said) on the right.
    var sign: AraSign {
        switch kind {
        case .working:
            return AraSign(
                tone: .working, icon: .symbol("circle.dotted"), mark: agent, markDetail: project,
                title: L10n.string("agents.notice.working"),
                subtitle: forecast?.estimatedCostPercent.map {
                    String(format: L10n.string("agents.notice.costShort"), Self.percent($0, about: true))
                },
                rows: limitRows(showsEstimate: true))
        case .attention(let message):
            return AraSign(
                tone: .attention, icon: .symbol("exclamationmark.bubble.fill"), mark: agent, markDetail: project,
                title: L10n.string("agents.notice.attention"),
                rows: AgentNoticeText.lines(of: message ?? "").map { AraSign.Row($0) })
        case .finished(let cost):
            var rows: [AraSign.Row] = []
            if let cost {
                rows.append(AraSign.Row(
                    L10n.string("agents.notice.spent"), detail: L10n.string("agents.notice.measured"),
                    badge: .disc(Self.percent(cost))))
            }
            return AraSign(
                tone: .plain, icon: .symbol("checkmark.circle.fill"), mark: agent, markDetail: project,
                title: L10n.string("agents.notice.finished"),
                rows: rows + limitRows(showsEstimate: false).prefix(rows.isEmpty ? 2 : 1))
        }
    }

    /// What is left of the five-hour limit and, for a turn that begins, what is expected to
    /// be left after it. An old number says when it is from, so it is not taken for the present.
    private func limitRows(showsEstimate: Bool) -> [AraSign.Row] {
        guard let forecast else { return [] }
        let window = forecast.isStale(at: now)
            ? String(format: L10n.string("agents.notice.asOfShort"), Self.time.string(from: forecast.asOf))
            : L10n.string("agents.notice.window")
        var rows = [AraSign.Row(
            L10n.string("agents.notice.now"), detail: window, badge: .digits(Self.percent(forecast.remainingPercent)))]
        if showsEstimate, let after = forecast.expectedRemainingPercent {
            rows.append(AraSign.Row(
                L10n.string("agents.notice.after"), detail: L10n.string("agents.notice.afterTurn"),
                badge: .digits(Self.percent(after, about: true))))
        }
        return rows
    }

    private static func percent(_ value: Double, about: Bool = false) -> String {
        (about ? "~" : "") + String(format: "%.0f%%", value)
    }

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// The notice as an activity of the notch.
    @MainActor
    func activity(id: String, duration: TimeInterval) -> NotchLiveActivity {
        NotchLiveActivity(id: id, priority: 2, duration: duration, pageID: "agents", sign: sign)
    }
}
