import AgentCore
import NotchCore
import NotchShell
import SwiftUI

/// The agents at work, as a widget of the overview. Small: how many sessions, whether one waits
/// for the user, and Claude's five-hour limit. Wide: the first two sessions as well. Large: up
/// to five sessions with when they last did something, and each agent's five-hour and
/// seven-day limits. Orange for a session waiting for the user and a limit used to 90%.
struct AgentWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    @ObservedObject var model: AgentViewModel
    let onOpen: () -> Void

    var body: some View {
        let sessions = model.sessions.sorted { Self.rank($0.state) < Self.rank($1.state) }
        let waiting = sessions.filter(\.isWaitingForUser).count
        AraWidget(name: L10n.string("page.agents.title"), hue: .lilac, onOpen: onOpen) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                switch size {
                case .small: small(sessions, waiting: waiting, now: timeline.date)
                case .wide: wide(sessions, waiting: waiting, now: timeline.date)
                case .large: large(sessions, waiting: waiting, now: timeline.date)
                }
            }
        }
    }

    private func small(_ sessions: [AgentSession], waiting: Int, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2 * ui) {
            AraWidgetHeader(label: L10n.string("widget.agents.label"), chip: waitingChip(waiting))
            Spacer(minLength: 0)
            if sessions.isEmpty {
                noneText
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4 * ui) {
                    AraBigValue("\(sessions.count)", size: 24)
                        .fixedSize()
                    Text(L10n.string("widget.agents.sessionsWord"))
                        .font(.system(size: 10.5 * ui))
                        .foregroundStyle(AraPalette.widgetSecondary)
                }
            }
            meter("Claude", model.claudeUsage?.fiveHour, now: now)
        }
    }

    private func wide(_ sessions: [AgentSession], waiting: Int, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1 * ui) {
            let more = sessions.count - 2
            AraWidgetHeader(
                label: L10n.string("widget.agents.label"),
                chip: waitingChip(waiting) ?? (more > 0 ? AraStatusChip(text: "+\(more)", hue: .lilac) : nil))
            if sessions.isEmpty {
                noneText
            }
            ForEach(sessions.prefix(2)) { session in
                row(session, now: nil)
            }
            Spacer(minLength: 0)
            meter(String(format: L10n.string("widget.agents.fiveHour"), "Claude"), model.claudeUsage?.fiveHour, now: now)
        }
    }

    private func large(_ sessions: [AgentSession], waiting: Int, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 1 * ui) {
            AraWidgetHeader(
                label: String(format: L10n.string("widget.agents.sessions"), sessions.count), chip: waitingChip(waiting))
            if sessions.isEmpty {
                noneText
            }
            ForEach(sessions.prefix(5)) { session in
                row(session, now: now)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 14 * ui) {
                limits("Claude", model.claudeUsage, now: now)
                // Codex not used for over a week: its old numbers say nothing now.
                limits("Codex", model.codexUsage.flatMap { $0.isOld(at: now) ? nil : $0 }, now: now)
            }
        }
    }

    private var noneText: some View {
        Text(L10n.string("widget.agents.none"))
            .font(.system(size: 12 * ui, weight: .semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    private func waitingChip(_ waiting: Int) -> AraStatusChip? {
        WidgetAlert.agents(waiting: waiting)
            ? AraStatusChip(text: String(format: L10n.string("widget.agents.waiting"), waiting), hue: .lilac, isAlert: true) : nil
    }

    /// A dot, the folder, the state; on a large widget also when it last did something.
    private func row(_ session: AgentSession, now: Date?) -> some View {
        HStack(spacing: 6 * ui) {
            Circle()
                .fill(Self.color(for: session.state))
                .frame(width: 7 * ui, height: 7 * ui)
            Text(session.project)
                .font(.system(size: 11 * ui, weight: .semibold))
                .lineLimit(1)
            Text(Self.word(for: session.state))
                .font(.system(size: 10.5 * ui))
                .foregroundStyle(session.isWaitingForUser ? AraPalette.alert : AraPalette.widgetSecondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            if let now {
                Text(Self.relative.localizedString(for: session.lastActivity, relativeTo: now))
                    .font(.system(size: 10.5 * ui))
                    .foregroundStyle(AraPalette.widgetSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 14 * ui)
        .accessibilityElement(children: .combine)
    }

    /// "Claude 62%" over its five-hour bar; nothing when the agent reported no limits.
    @ViewBuilder
    private func meter(_ label: String, _ window: UsageWindow?, now: Date) -> some View {
        if window != nil, window?.current(at: now) == nil {
            // Reported once, but the window has reset since: what is used now is not known.
            Text("\(label) · \(L10n.string("page.agents.usage.unknown").lowercased())")
                .font(.system(size: 10.5 * ui))
                .foregroundStyle(AraPalette.widgetSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else if let window = window?.current(at: now) {
            HStack(spacing: 6 * ui) {
                Text(label)
                    .foregroundStyle(AraPalette.widgetSecondary)
                    .lineLimit(1)
                    .fixedSize()
                AraTrackBar(fraction: window.usedPercent / 100, hue: .lilac, isAlert: WidgetAlert.usage(percent: window.usedPercent))
                Text("\(Int(window.usedPercent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(WidgetAlert.usage(percent: window.usedPercent) ? AraPalette.alert : AraPalette.widgetText)
                    .fixedSize()
            }
            .font(.system(size: 10.5 * ui, weight: .semibold))
            .help(UsageMeter.resetText(window, now: now))
        }
    }

    /// One agent's limits: the five-hour bar, the seven-day one thin under it, when the window starts again.
    @ViewBuilder
    private func limits(_ label: String, _ usage: AgentUsage?, now: Date) -> some View {
        if usage?.fiveHour != nil, usage?.fiveHour?.current(at: now) == nil {
            meter(label, usage?.fiveHour, now: now)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if let five = usage?.fiveHour?.current(at: now) {
            VStack(alignment: .leading, spacing: 2 * ui) {
                HStack(spacing: 6 * ui) {
                    Text(String(format: L10n.string("widget.agents.fiveHour"), label))
                        .foregroundStyle(AraPalette.widgetSecondary)
                    Spacer(minLength: 0)
                    Text("\(Int(five.usedPercent.rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(WidgetAlert.usage(percent: five.usedPercent) ? AraPalette.alert : AraPalette.widgetText)
                }
                .font(.system(size: 10.5 * ui, weight: .semibold))
                .lineLimit(1)
                AraTrackBar(fraction: five.usedPercent / 100, hue: .lilac, isAlert: WidgetAlert.usage(percent: five.usedPercent))
                if let seven = usage?.sevenDay?.current(at: now) {
                    AraTrackBar(fraction: seven.usedPercent / 100, hue: .lilac, isAlert: WidgetAlert.usage(percent: seven.usedPercent), thin: true)
                }
                Text(UsageMeter.resetText(five, now: now))
                    .font(.system(size: 10.5 * ui))
                    .foregroundStyle(AraPalette.widgetSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Waiting for the user comes first, then working, then the rest.
    private static func rank(_ state: AgentSession.State) -> Int {
        switch state {
        case .waiting: 0
        case .working: 1
        case .done, .stopped: 2
        case .idle: 3
        }
    }

    private static func color(for state: AgentSession.State) -> Color {
        switch state {
        case .waiting: AraPalette.alert
        case .working: AraPalette.vivid(.lilac)
        case .done, .idle, .stopped: AraPalette.widgetSecondary
        }
    }

    private static func word(for state: AgentSession.State) -> String {
        switch state {
        case .idle: L10n.string("page.agents.state.idle")
        case .working: L10n.string("page.agents.state.working")
        case .waiting: L10n.string("page.agents.state.waiting")
        case .done: L10n.string("page.agents.state.done")
        case .stopped: L10n.string("page.agents.state.stopped")
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
