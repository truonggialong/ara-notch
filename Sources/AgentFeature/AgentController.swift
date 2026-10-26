import AgentCore
import AppKit
import Combine
import NotchShell
import SwiftUI

/// Observable agent settings; every change is written through to the store.
@MainActor
public final class AgentSettings: ObservableObject {
    private let store: AgentSettingsStore

    @Published public var announcesAttention: Bool {
        didSet { store.announcesAttention = announcesAttention }
    }

    @Published public var announcesFinished: Bool {
        didSet { store.announcesFinished = announcesFinished }
    }

    @Published public var tracksCodex: Bool {
        didSet { store.tracksCodex = tracksCodex }
    }

    /// Ask the Claude account for its rate limits, with Claude Code's sign-in in the keychain.
    @Published public var readsClaudeAccount: Bool {
        didSet { store.readsClaudeAccount = readsClaudeAccount }
    }

    /// Say so under the notch when an agent sets to work on a request.
    @Published public var announcesWorking: Bool {
        didSet { store.announcesWorking = announcesWorking }
    }

    /// What measured turns took from the five-hour limit, kept between launches.
    func turnCosts(codex: Bool) -> [Double] {
        store.turnCosts(codex: codex)
    }

    func setTurnCosts(_ costs: [Double], codex: Bool) {
        store.setTurnCosts(costs, codex: codex)
    }

    public init(store: AgentSettingsStore) {
        self.store = store
        announcesWorking = store.announcesWorking
        announcesAttention = store.announcesAttention
        announcesFinished = store.announcesFinished
        tracksCodex = store.tracksCodex
        readsClaudeAccount = store.readsClaudeAccount
    }
}

/// State the Agents page and its settings render from.
@MainActor
final class AgentViewModel: ObservableObject {
    @Published var sessions: [AgentSession] = []
    @Published var hooksInstalled = false
    /// Localized outcome of the last install or removal.
    @Published var hooksMessage: String?

    /// Rate limits as last reported; nil until something reported them.
    @Published var claudeUsage: AgentUsage?
    /// How the last ask of the Claude account went, for Settings.
    @Published var claudeAccountState = ClaudeAccountReader.State.off
    @Published var codexUsage: AgentUsage?
    @Published var statusLineState = ClaudeStatusLineInstaller.State.absent
    @Published var statusLineMessage: String?
    /// Codex's session folder exists on this Mac.
    @Published var codexAvailable = false

    /// Bring the app at this path forward: the one a session runs in.
    var onOpenHost: ((String) -> Void)?
    var onInstallHooks: (() -> Void)?
    var onRemoveHooks: (() -> Void)?
    var onInstallStatusLine: (() -> Void)?
    var onRemoveStatusLine: (() -> Void)?
}

/// Follows Claude Code sessions through hooks and shows them on the notch.
@MainActor
public final class AgentController {
    /// A session with no activity for this long is forgotten.
    private static let sessionLifetime: TimeInterval = 12 * 3600

    private let settings: AgentSettings
    private let notch: NotchController
    private let viewModel = AgentViewModel()
    private let spool: AgentEventSpool
    private let hooks: ClaudeHooks
    private let codex: CodexWatcher
    private let usageFile: URL
    private let account = ClaudeAccountReader()
    private var usageFileDate: Date?
    private var cancellables = Set<AnyCancellable>()
    private var sessions = AgentSessions()
    /// Sessions open in a running Claude Code, as last read; they are kept however quiet.
    private var runningClaudeIDs: Set<String> = []
    /// Until the running sessions have been read once, no session is forgotten: the history
    /// read at launch would otherwise drop the ones a running Claude Code still has open.
    private var hasReadRunningSessions = false
    private var sessionCheck: Timer?
    private var isCheckingSessions = false
    private let claudeProjects: URL
    /// What turns took from each agent's five-hour limit, for estimating the next one.
    private var claudeCosts: TurnCostLedger
    private var codexCosts: TurnCostLedger
    /// Events already on file at launch are history; only later ones are announced.
    private var announcesEvents = false

    /// - Parameters:
    ///   - eventsFile: where the hook helper writes; nil for the standard place.
    ///   - claudeSettingsFile: Claude Code's settings file; nil for `~/.claude/settings.json`.
    ///   - usageFile: where the status line helper writes Claude's rate limits; nil for the standard place.
    ///   - codexSessionsDirectory: Codex's session logs; nil for `~/.codex/sessions`.
    public init(
        settings: AgentSettings, notch: NotchController, eventsFile: URL? = nil, claudeSettingsFile: URL? = nil,
        usageFile: URL? = nil, codexSessionsDirectory: URL? = nil, claudeProjectsDirectory: URL? = nil
    ) {
        claudeProjects = claudeProjectsDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        self.settings = settings
        self.notch = notch
        claudeCosts = TurnCostLedger(costs: settings.turnCosts(codex: false))
        codexCosts = TurnCostLedger(costs: settings.turnCosts(codex: true))
        spool = AgentEventSpool(file: eventsFile)
        hooks = ClaudeHooks(settingsFile: claudeSettingsFile)
        codex = CodexWatcher(directory: codexSessionsDirectory)
        self.usageFile = usageFile ?? spool.file.deletingLastPathComponent().appendingPathComponent("claude-usage.json")
        spool.onTick = { [weak self] in self?.readClaudeUsage() }
        account.onUsage = { [weak self] usage in self?.takeClaudeUsage(usage) }
        account.onState = { [weak self] state in self?.viewModel.claudeAccountState = state }
        codex.onEvents = { [weak self] events in self?.applyCodex(events) }
        viewModel.onInstallStatusLine = { [weak self] in self?.installStatusLine() }
        viewModel.onRemoveStatusLine = { [weak self] in self?.removeStatusLine() }
        spool.onEvents = { [weak self] events in self?.apply(events) }
        viewModel.onOpenHost = { [weak self] path in
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
            self?.notch.close()
        }
        viewModel.onInstallHooks = { [weak self] in self?.installHooks() }
        viewModel.onRemoveHooks = { [weak self] in self?.removeHooks() }
    }

    public func start() {
        hooks.refreshHelperIfInstalled()
        viewModel.hooksInstalled = hooks.isInstalled
        viewModel.statusLineState = hooks.statusLineState
        viewModel.codexAvailable = FileManager.default.fileExists(atPath: codex.directory.path)
        spool.start()
        // Codex logs already on disk are history too; the switch below reads them before
        // announcements are turned on.
        settings.$tracksCodex
            .sink { [weak self] isOn in self?.setTracksCodex(isOn) }
            .store(in: &cancellables)
        let check = Timer(timeInterval: Self.sessionCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSessions() }
        }
        RunLoop.main.add(check, forMode: .common)
        sessionCheck = check
        checkSessions()
        settings.$readsClaudeAccount
            .sink { [weak self] isOn in isOn ? self?.account.start() : self?.account.stop() }
            .store(in: &cancellables)
        announcesEvents = true
    }

    // MARK: - Rate limits and Codex

    /// Sets Claude Code's status line to this app's helper, which is the only way to be told
    /// the rate limits. The settings file is backed up first.
    public func installStatusLine() {
        do {
            let backup = try hooks.installStatusLine()
            viewModel.statusLineMessage = backup.map {
                String(format: L10n.string("settings.agents.statusLine.installed.backup"), $0.lastPathComponent)
            } ?? L10n.string("settings.agents.statusLine.installed")
        } catch ClaudeHooks.Problem.foreignStatusLine {
            viewModel.statusLineMessage = L10n.string("settings.agents.statusLine.foreign")
        } catch {
            viewModel.statusLineMessage = String(format: L10n.string("settings.agents.hooks.failed"), String(describing: error))
        }
        viewModel.statusLineState = hooks.statusLineState
    }

    public func removeStatusLine() {
        do {
            try hooks.uninstallStatusLine()
            viewModel.statusLineMessage = L10n.string("settings.agents.statusLine.removed")
        } catch {
            viewModel.statusLineMessage = String(format: L10n.string("settings.agents.hooks.failed"), String(describing: error))
        }
        viewModel.statusLineState = hooks.statusLineState
    }

    /// Reads the file the status line helper writes, when it has changed.
    private func readClaudeUsage() {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: usageFile.path))?[.modificationDate] as? Date,
              modified != usageFileDate
        else { return }
        usageFileDate = modified
        guard let text = try? String(contentsOf: usageFile, encoding: .utf8),
              let usage = AgentUsage(record: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return }
        takeClaudeUsage(usage)
    }

    /// A report from the status line or the account: the newer one stands.
    private func takeClaudeUsage(_ usage: AgentUsage) {
        viewModel.claudeUsage = AgentUsage.latest(viewModel.claudeUsage, usage)
    }

    private func setTracksCodex(_ isOn: Bool) {
        if isOn {
            codex.start()
        } else {
            codex.stop()
            viewModel.codexUsage = nil
            // Codex sessions leave the list; Claude Code's stay.
            let codexEnds = sessions.list.filter(\.isCodex).map {
                AgentEvent(kind: .sessionEnd, sessionID: $0.id, cwd: nil, toolName: nil, message: nil, at: Date())
            }
            apply(codexEnds)
        }
    }

    private func applyCodex(_ events: [(sessionID: String, event: CodexRolloutEvent)]) {
        var agentEvents: [AgentEvent] = []
        for (sessionID, event) in events {
            if case .usage(let usage) = event {
                // The newest report stands, whichever session it came from.
                if usage.updatedAt >= (viewModel.codexUsage?.updatedAt ?? .distantPast) {
                    viewModel.codexUsage = usage
                }
            } else if let agentEvent = CodexRolloutEvent.agentEvent(for: event, sessionID: sessionID) {
                agentEvents.append(agentEvent)
            }
        }
        apply(agentEvents)
    }

    /// What the app currently knows, as text; for automated checks.
    public var summary: String {
        func usage(_ name: String, _ usage: AgentUsage?) -> String {
            guard let usage else { return "\(name) usage: none" }
            let five = usage.fiveHour.map { "\(Int($0.usedPercent.rounded()))%" } ?? "-"
            let seven = usage.sevenDay.map { "\(Int($0.usedPercent.rounded()))%" } ?? "-"
            return "\(name) usage: 5h \(five), 7d \(seven)"
        }
        let list = sessions.list.map { "\($0.isCodex ? "codex" : "claude") \($0.project) \($0.state)" }
        return ([usage("claude", viewModel.claudeUsage), usage("codex", viewModel.codexUsage),
                 "status line: \(viewModel.statusLineState)", "sessions: \(list.count)"] + list).joined(separator: "\n")
    }

    /// The sessions and their states, as a tile of the overview page.
    public func makeOverviewTile() -> AnyView {
        AnyView(AgentWidget(model: viewModel) { [weak notch] in notch?.selectPage(id: "agents") })
    }


    public func makePage() -> NotchPage {
        NotchPage(
            id: "agents", titleKey: "page.agents.title", symbolName: "terminal", hue: .lilac
        ) { [viewModel] in
            AgentPageView(model: viewModel)
        }
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(AgentSettingsSection(settings: settings, model: viewModel))
    }

    /// Which moments of a turn are announced, for Settings › Notices.
    public func makeNoticeSettings() -> AnyView {
        AnyView(AgentNoticeSettings(settings: settings))
    }

    /// Adds the hooks to Claude Code's settings, after backing the file up.
    public func installHooks() {
        do {
            let backup = try hooks.install()
            viewModel.hooksMessage = backup.map {
                String(format: L10n.string("settings.agents.hooks.installed.backup"), $0.lastPathComponent)
            } ?? L10n.string("settings.agents.hooks.installed")
        } catch {
            viewModel.hooksMessage = String(format: L10n.string("settings.agents.hooks.failed"), String(describing: error))
        }
        viewModel.hooksInstalled = hooks.isInstalled
    }

    /// Takes the hooks and the status line out of a Claude Code settings file, for removing
    /// AraNotch from the Mac. The file is backed up first and otherwise left as it was.
    public func removeFromClaudeCode(settingsFile: URL) throws {
        try ClaudeHooks(settingsFile: settingsFile).uninstallAll()
    }

    public func removeHooks() {
        do {
            try hooks.uninstall()
            viewModel.hooksMessage = L10n.string("settings.agents.hooks.removed")
        } catch {
            viewModel.hooksMessage = String(format: L10n.string("settings.agents.hooks.failed"), String(describing: error))
        }
        viewModel.hooksInstalled = hooks.isInstalled
    }

    private func apply(_ events: [AgentEvent]) {
        // The limits as they stand now: a turn is measured against them as it begins and ends.
        readClaudeUsage()
        for event in events {
            let announcement = sessions.apply(event)
            // Events already on file at launch are history: neither announced nor measured.
            guard announcesEvents else { continue }
            let isCodex = event.sessionID.hasPrefix("codex:")
            if event.kind == .sessionEnd {
                forgetTurn(of: event.sessionID, isCodex: isCodex)
            }
            guard let announcement, let session = sessions.session(id: event.sessionID) else { continue }
            let usage = isCodex ? viewModel.codexUsage : viewModel.claudeUsage
            switch announcement {
            case .started:
                beginTurn(of: session.id, isCodex: isCodex, usage: usage, at: event.at)
                if settings.announcesWorking {
                    announce(.working, session, usage: usage, duration: 5)
                }
            case .needsAttention:
                if settings.announcesAttention {
                    var message: String?
                    if case .waiting(let said) = session.state { message = said }
                    announce(.attention(message: message), session, usage: usage, duration: 6)
                }
            case .finished:
                let cost = endTurn(of: session.id, isCodex: isCodex, usage: usage, at: event.at)
                if settings.announcesFinished {
                    announce(.finished(costPercent: cost), session, usage: usage, duration: 4)
                }
            }
        }
        if hasReadRunningSessions {
            sessions.expire(before: Date().addingTimeInterval(-Self.sessionLifetime), keeping: runningClaudeIDs)
        }
        viewModel.sessions = sessions.list
    }

    // MARK: - Turns that end without a word

    private static let sessionCheckInterval: TimeInterval = 20
    /// A turn that goes on reports each tool it uses; one quiet this long has stopped.
    private static let quietTurnLimit: TimeInterval = 30 * 60

    /// Claude Code says nothing when the user stops a turn, and nothing when a session it
    /// still has open has been quiet for days. Every 20 seconds: which sessions a running
    /// Claude Code has open, and whether the quiet turns were stopped, read from the end of
    /// their transcripts.
    private func checkSessions() {
        guard !isCheckingSessions else { return }
        isCheckingSessions = true
        let quiet = Date().addingTimeInterval(-Self.sessionCheckInterval)
        let candidates = sessions.list.filter { !$0.isCodex && $0.isMidTurn && $0.lastActivity < quiet }.map(\.id)
        let projects = claudeProjects
        Task.detached(priority: .utility) {
            let running = ClaudeSessionProbe.runningSessionIDs()
            let stopped = candidates.filter { ClaudeSessionProbe.wasInterrupted(sessionID: $0, projects: projects) }
            await MainActor.run { [weak self] in self?.finishCheck(running: running, stopped: stopped) }
        }
    }

    private func finishCheck(running: Set<String>?, stopped: [String]) {
        isCheckingSessions = false
        if let running {
            runningClaudeIDs = running
            hasReadRunningSessions = true
        }
        stopped.forEach { sessions.markStopped(id: $0) }
        let now = Date()
        sessions.stopTurns(quietSince: now.addingTimeInterval(-Self.quietTurnLimit))
        if hasReadRunningSessions {
            sessions.expire(before: now.addingTimeInterval(-Self.sessionLifetime), keeping: runningClaudeIDs)
        }
        if viewModel.sessions != sessions.list {
            viewModel.sessions = sessions.list
        }
    }

    // MARK: - What turns take

    private func beginTurn(of sessionID: String, isCodex: Bool, usage: AgentUsage?, at date: Date) {
        if isCodex {
            codexCosts.begin(sessionID: sessionID, usage: usage, at: date)
        } else {
            claudeCosts.begin(sessionID: sessionID, usage: usage, at: date)
        }
    }

    /// What the turn took from the five-hour limit, when that could be measured; kept for
    /// the estimates to come.
    private func endTurn(of sessionID: String, isCodex: Bool, usage: AgentUsage?, at date: Date) -> Double? {
        let cost: Double?
        if isCodex {
            cost = codexCosts.end(sessionID: sessionID, usage: usage, at: date)
        } else {
            cost = claudeCosts.end(sessionID: sessionID, usage: usage, at: date)
        }
        if cost != nil {
            settings.setTurnCosts(isCodex ? codexCosts.costs : claudeCosts.costs, codex: isCodex)
        }
        return cost
    }

    private func forgetTurn(of sessionID: String, isCodex: Bool) {
        if isCodex {
            codexCosts.forget(sessionID: sessionID)
        } else {
            claudeCosts.forget(sessionID: sessionID)
        }
    }

    /// Drops a notice out of the notch: which agent, what it is at, and its limit.
    private func announce(_ kind: AgentNotice.Kind, _ session: AgentSession, usage: AgentUsage?, duration: TimeInterval) {
        let now = Date()
        let costs = session.isCodex ? codexCosts.costs : claudeCosts.costs
        let notice = AgentNotice(
            kind: kind, agent: session.isCodex ? "Codex" : "Claude", project: session.project,
            forecast: UsageForecast(usage: usage, costs: costs, now: now), now: now)
        notch.present(notice.activity(id: "agents.\(session.id)", duration: duration))
    }
}

/// The Agents page of the notch: one row per Claude Code session.
struct AgentPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: AgentViewModel

    var body: some View {
        VStack(spacing: 6 * ui) {
            usageStrip
            sessionList
        }
    }

    /// The rate limits of each agent that reported any: the five-hour window and the weekly one.
    @ViewBuilder
    private var usageStrip: some View {
        if model.claudeUsage != nil || model.codexUsage.map({ !$0.isOld(at: Date()) }) == true {
            // Redrawn every minute, so a window that has reset shows as empty.
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                HStack(spacing: 8 * ui) {
                    if let usage = model.claudeUsage {
                        usageChip("Claude", usage, now: timeline.date)
                    }
                    // Codex not used for over a week: its old numbers say nothing now.
                    if let usage = model.codexUsage, !usage.isOld(at: timeline.date) {
                        usageChip("Codex", usage, now: timeline.date)
                    }
                }
            }
            .padding(.horizontal, 4 * ui)
        }
    }

    private func usageChip(_ name: String, _ usage: AgentUsage, now: Date) -> some View {
        HStack(spacing: 8 * ui) {
            AraLabel(name)
            if let window = usage.fiveHour?.current(at: now) {
                usageMeter(L10n.string("page.agents.usage.fiveHour"), window, now: now)
            }
            if let window = usage.sevenDay?.current(at: now) {
                usageMeter(L10n.string("page.agents.usage.sevenDay"), window, now: now)
            }
            // Both windows reset since the last report: what is used now is not known.
            if usage.fiveHour?.current(at: now) == nil, usage.sevenDay?.current(at: now) == nil {
                Text(name == "Claude" ? Self.claudeUnknown(model.claudeAccountState) : L10n.string("page.agents.usage.unknown"))
                    .font(.system(size: 10 * ui))
                    .foregroundStyle(AraTheme.secondaryText)
            }
        }
        .padding(.horizontal, 10 * ui)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 26 * ui)
        .araSurface(Capsule())
    }

    /// Why Claude has no new numbers, and what gives them.
    static func claudeUnknown(_ state: ClaudeAccountReader.State) -> String {
        switch state {
        case .off: L10n.string("page.agents.usage.unknown.off")
        case .expired: L10n.string("settings.agents.account.expired")
        case .refused: L10n.string("settings.agents.account.refused")
        case .noLogin: L10n.string("settings.agents.account.noLogin")
        case .reading, .read, .failed: L10n.string("page.agents.usage.unknown")
        }
    }

    private func usageMeter(_ label: String, _ window: UsageWindow, now: Date) -> some View {
        UsageMeter(label: label, window: window, now: now)
    }

    @ViewBuilder
    private var sessionList: some View {
        if model.sessions.isEmpty {
            AraEmptyState(
                icon: .agents,
                title: L10n.string(model.hooksInstalled ? "page.agents.empty" : "page.agents.notInstalled"))
        } else {
            ScrollView(showsIndicators: false) {
                // Redrawn every half minute so the "… ago" times stay right.
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    VStack(spacing: 4 * ui) {
                        ForEach(model.sessions) { session in
                            row(session, now: timeline.date)
                        }
                    }
                }
                .padding(.horizontal, 4 * ui)
                .padding(.bottom, 10 * ui)
            }
            .araScrollFade()
        }
    }

    /// A session whose app is known is a button: it brings that app forward.
    @ViewBuilder
    private func row(_ session: AgentSession, now: Date) -> some View {
        if let hostApp = session.hostApp {
            AraHoverLift(scale: 1.012) { isHovered in
                Button {
                    model.onOpenHost?(hostApp)
                } label: {
                    rowContent(session, now: now, isHovered: isHovered)
                }
                .buttonStyle(AraPressStyle(depth: 0.98))
                .araTooltip(
                    String(format: L10n.string("page.agents.open"), FileManager.default.displayName(atPath: hostApp)),
                    isHovered: isHovered)
            }
        } else {
            rowContent(session, now: now, isHovered: false)
        }
    }

    private func rowContent(_ session: AgentSession, now: Date, isHovered: Bool) -> some View {
        HStack(spacing: 9 * ui) {
            Image(systemName: Self.symbol(for: session.state))
                .font(.system(size: 12 * ui))
                .foregroundStyle(Self.color(for: session.state))
                .frame(width: 18 * ui)
            Text(session.project)
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(1)
            if session.isCodex {
                Text("Codex")
                    .font(.system(size: 10 * ui, weight: .semibold))
                    .padding(.horizontal, 5 * ui)
                    .frame(height: 15 * ui)
                    .overlay { Capsule().strokeBorder(AraPalette.hairline, lineWidth: 1 * ui) }
            }
            // The state as the card writes a fact: WORKING | the tool, WAITING | the question.
            let facts = Self.facts(of: session.state)
            if let detail = facts.detail {
                AraFactRow(facts.state, detail)
            } else {
                AraLabel(facts.state)
            }
            Spacer(minLength: 8 * ui)
            // The formatter would say "in 0 sec" for the first minute.
            Text(now.timeIntervalSince(session.lastActivity) < 60
                ? L10n.string("clipboard.time.now")
                : Self.relative.localizedString(for: session.lastActivity, relativeTo: now))
                .font(.system(size: 10 * ui, weight: .medium))
                .foregroundStyle(AraPalette.value)
        }
        .padding(.horizontal, 10 * ui)
        .frame(height: 30 * ui)
        // A session waiting for the user takes the page's lilac, so it is found at a glance.
        .araCard(
            radius: AraTheme.rowRadius, level: isHovered || session.state != .idle ? .raised : .plate,
            hue: session.isWaitingForUser ? .lilac : nil)
        .contentShape(RoundedRectangle(cornerRadius: AraTheme.rowRadius * ui, style: .continuous))
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func symbol(for state: AgentSession.State) -> String {
        switch state {
        case .idle: "circle"
        case .working: "gearshape.2.fill"
        case .waiting: "exclamationmark.bubble.fill"
        case .done: "checkmark.circle.fill"
        case .stopped: "stop.circle"
        }
    }

    private static func color(for state: AgentSession.State) -> Color {
        switch state {
        case .idle: AraPalette.ink.opacity(0.4)
        case .working: AraPalette.value
        case .waiting: AraPalette.warning
        case .done: AraPalette.value
        case .stopped: AraPalette.ink.opacity(0.4)
        }
    }

    /// The state in a word, and what it is busy with or asking, when it said.
    private static func facts(of state: AgentSession.State) -> (state: String, detail: String?) {
        switch state {
        case .idle:
            (L10n.string("page.agents.state.idle"), nil)
        case .working(let tool):
            (L10n.string("page.agents.state.working"), tool.map(AgentToolName.display))
        case .waiting(let message):
            (L10n.string("page.agents.state.waiting"), message)
        case .done:
            (L10n.string("page.agents.state.done"), nil)
        case .stopped:
            (L10n.string("page.agents.state.stopped"), nil)
        }
    }
}

/// The Agents tab of the Settings window.
struct AgentSettingsSection: View {
    @ObservedObject var settings: AgentSettings
    @ObservedObject var model: AgentViewModel

    var body: some View {
        Section(L10n.string("settings.agents.claude")) {
            // A switch, as the rest of Settings: on puts the hooks in Claude Code's settings.
            Toggle(isOn: Binding(
                get: { model.hooksInstalled },
                set: { $0 ? model.onInstallHooks?() : model.onRemoveHooks?() }
            )) {
                Text(L10n.string("settings.agents.hooks"))
                AraSettingsNote(model.hooksMessage ?? L10n.string("settings.agents.hooks.note"))
            }
            Toggle(isOn: Binding(
                get: { model.statusLineState == .installed },
                set: { $0 ? model.onInstallStatusLine?() : model.onRemoveStatusLine?() }
            )) {
                Text(L10n.string("settings.agents.statusLine"))
                AraSettingsNote(model.statusLineMessage ?? L10n.string(
                    model.statusLineState == .foreign ? "settings.agents.statusLine.foreign" : "settings.agents.statusLine.note"))
            }
            // Another status line is the user's own: it is not replaced from here.
            .disabled(model.statusLineState == .foreign)
            Toggle(isOn: $settings.readsClaudeAccount) {
                Text(L10n.string("settings.agents.account"))
                AraSettingsNote(accountNote)
            }
        }
        Section(L10n.string("settings.agents.codexTitle")) {
            Toggle(isOn: $settings.tracksCodex) {
                Text(L10n.string("settings.agents.codex"))
                AraSettingsNote(L10n.string(model.codexAvailable ? "settings.agents.codex.note" : "settings.agents.codex.missing"))
            }
            .disabled(!model.codexAvailable && !settings.tracksCodex)
        }
    }
}

extension AgentSettingsSection {
    /// What reading the account does, and how the last read went.
    var accountNote: String {
        switch model.claudeAccountState {
        case .off: L10n.string("settings.agents.account.note")
        case .reading: L10n.string("settings.agents.account.reading")
        case .read(let date):
            String(format: L10n.string("settings.agents.account.read"), date.formatted(date: .omitted, time: .shortened))
        case .noLogin: L10n.string("settings.agents.account.noLogin")
        case .refused: L10n.string("settings.agents.account.refused")
        case .expired: L10n.string("settings.agents.account.expired")
        case .failed(let status): String(format: L10n.string("settings.agents.account.failed"), status)
        }
    }
}

/// When agents speak, in Settings › Notices: one chip each.
struct AgentNoticeSettings: View {
    @ObservedObject var settings: AgentSettings

    var body: some View {
        AraChipRow(titleKey: "settings.agents.announce", chips: [
            .init(id: "working", title: L10n.string("settings.agents.announceWorking"), isOn: $settings.announcesWorking),
            .init(id: "attention", title: L10n.string("settings.agents.announceAttention"), isOn: $settings.announcesAttention),
            .init(id: "finished", title: L10n.string("settings.agents.announceFinished"), isOn: $settings.announcesFinished),
        ])
    }
}

/// How much of a rate-limit window is used: a short bar that turns orange at 70% and red at
/// 90%, with the percentage; when it resets shows under the pointer.
struct UsageMeter: View {
    @Environment(\.araScale) private var ui
    let label: String
    let window: UsageWindow
    let now: Date

    var body: some View {
        let fraction = min(max(window.usedPercent / 100, 0), 1)
        let color = window.usedPercent >= 90 ? AraPalette.danger : window.usedPercent >= 70 ? AraPalette.warning : AraPalette.value
        HStack(spacing: 4 * ui) {
            Text(label)
                .foregroundStyle(AraPalette.ink.opacity(0.55))
            ZStack(alignment: .leading) {
                Capsule().fill(AraPalette.track)
                Capsule().fill(color).frame(width: 34 * fraction)
            }
            .frame(width: 34 * ui, height: 4 * ui)
            Text("\(Int(window.usedPercent.rounded()))%")
                .monospacedDigit()
        }
        .font(.system(size: 10 * ui, weight: .medium))
        .help(Self.resetText(window, now: now))
    }

    /// When the window starts again, as shown under the pointer; empty when not known.
    static func resetText(_ window: UsageWindow, now: Date) -> String {
        window.resetsAt.map {
            String(format: L10n.string("page.agents.usage.resets"), relative.localizedString(for: $0, relativeTo: now))
        } ?? ""
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
