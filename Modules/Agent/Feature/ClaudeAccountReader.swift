import AgentCore
import Foundation

/// Reads Claude's rate limits now and then (`AgentPacing`), from the first source that has them:
/// 1. Claude Code itself, asked as `/usage` asks (`ClaudeCodeUsageProbe`): no keychain read.
///    While it answers without numbers it is asked less and less (`AgentPacing.claudeCodeWait`).
/// 2. The history the Claude app saves as it checks (`ClaudeAppUsage`), when fresh.
/// 3. The Claude account, asked with the sign-in Claude Code keeps in the keychain.
/// This works whatever runs Claude Code, the desktop app's Code tab included, which never runs
/// the status line.
///
/// The access token is read from the keychain only when there is none in memory or it was
/// refused, and is never written anywhere, logged or renewed: Claude Code renews it itself.
@MainActor
final class ClaudeAccountReader {
    enum State: Equatable {
        case off
        case reading
        case read(at: Date, source: Source)
        /// No Claude Code sign-in in the keychain.
        case noLogin
        /// The user did not allow the keychain read.
        case refused
        /// The sign-in is out of date; Claude Code renews it when it next runs.
        case expired
        case failed(status: Int)
    }

    /// Where a reading came from.
    enum Source: Equatable, Sendable {
        case claudeCode, claudeApp, account
    }

    var onUsage: ((AgentUsage) -> Void)?
    var onState: ((State) -> Void)?

    /// The next check, set after each one (`AgentPacing.accountDelay`): every minute while the
    /// agent page shows, every five otherwise, and longer and longer after failed checks.
    private var timer: Timer?
    private var isOn = false
    private var token: String?
    private var isReading = false
    private var failures = 0
    private var lastRead: Date?
    private var pageShown = false
    /// Answers from Claude Code without numbers in a row, and when to ask it again.
    private var claudeCodeEmpties = 0
    private var claudeCodeAskAfter = Date.distantPast

    func start() {
        guard !isOn else { return }
        isOn = true
        read()
    }

    func stop() {
        isOn = false
        timer?.invalidate()
        timer = nil
        token = nil
        failures = 0
        claudeCodeEmpties = 0
        claudeCodeAskAfter = .distantPast
        onState?(.off)
    }

    /// The agent page came into view or went away. In view, a reading over a minute old is
    /// renewed at once.
    func setPageShown(_ shown: Bool) {
        guard shown != pageShown else { return }
        pageShown = shown
        guard isOn, !isReading else { return }
        if shown, failures == 0, AgentPacing.accountIsStale(lastRead: lastRead, now: Date()) {
            read()
        } else {
            schedule()
        }
    }

    private func schedule() {
        timer?.invalidate()
        guard isOn else { return }
        var delay = AgentPacing.accountDelay(pageShown: pageShown, failures: failures)
        if failures == 0, let lastRead {
            delay = max(delay - Date().timeIntervalSince(lastRead), 1)
        }
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        timer.tolerance = min(delay * 0.1, 10)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func read() {
        guard isOn, !isReading else { return }
        timer?.invalidate()
        timer = nil
        isReading = true
        onState?(.reading)
        let known = token
        let asksClaudeCode = Date() >= claudeCodeAskAfter
        Task.detached(priority: .utility) {
            let code = asksClaudeCode ? ClaudeCodeUsageProbe.ask() : nil
            let outcome: Outcome
            if case .usage(let usage) = code {
                outcome = .usage(usage, token: nil, source: .claudeCode)
            } else if let data = try? Data(contentsOf: ClaudeAppUsage.historyURL()),
                      let usage = ClaudeAppUsage.usage(from: data, now: Date()) {
                outcome = .usage(usage, token: nil, source: .claudeApp)
            } else {
                outcome = await Self.fetch(knownToken: known)
            }
            await MainActor.run { [weak self] in self?.finish(outcome, claudeCode: code) }
        }
    }

    private func finish(_ outcome: Outcome, claudeCode: ClaudeCodeUsageProbe.Outcome?) {
        isReading = false
        guard isOn else { return }
        switch claudeCode {
        case nil: break
        case .usage:
            claudeCodeEmpties = 0
            claudeCodeAskAfter = .distantPast
        case .empty, .failed, .missing:
            claudeCodeEmpties += 1
            claudeCodeAskAfter = Date().addingTimeInterval(AgentPacing.claudeCodeWait(empties: claudeCodeEmpties))
        }
        switch outcome {
        case .usage(let usage, let token, let source):
            if let token { self.token = token }
            failures = 0
            lastRead = Date()
            onUsage?(usage)
            onState?(.read(at: usage.updatedAt, source: source))
        case .state(let state):
            token = nil
            failures += 1
            onState?(state)
        }
        schedule()
    }

    private enum Outcome: Sendable {
        case usage(AgentUsage, token: String?, source: Source)
        case state(State)
    }

    /// Off the main thread: the keychain read waits while macOS asks the user.
    nonisolated private static func fetch(knownToken: String?) async -> Outcome {
        let token: String
        if let knownToken {
            token = knownToken
        } else {
            switch readLogin() {
            case .success(.valid(let accessToken)): token = accessToken
            case .success(.expired): return .state(.expired)
            case .failure(let error): return .state(error.state)
            }
        }
        var request = URLRequest(url: ClaudeAccountUsage.address, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("AraNotch", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return .state(.failed(status: 0)) }
        switch status {
        case 200:
            guard let usage = ClaudeAccountUsage.usage(from: data, at: Date()) else { return .state(.failed(status: 200)) }
            return .usage(usage, token: token, source: .account)
        case 401:
            // A token kept from an earlier read may have been renewed by Claude Code since.
            return knownToken == nil ? .state(.expired) : await fetch(knownToken: nil)
        default:
            return .state(.failed(status: status))
        }
    }

    /// Through Apple's `security` tool, as Claude Code itself reads and writes the item: its access
    /// list trusts that tool. A read from this app is tied to the code hash of this build (the signing
    /// certificate has no team), so every new build made macOS ask for the login password again.
    nonisolated private static func readLogin() -> Result<ClaudeLogin, StateError> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", ClaudeLogin.keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .failure(StateError(.failed(status: -1))) }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return login(exitStatus: process.terminationStatus, output: data, now: Date())
    }

    /// `security` exits with the low byte of the keychain status.
    nonisolated static func login(exitStatus: Int32, output: Data, now: Date) -> Result<ClaudeLogin, StateError> {
        switch exitStatus {
        case 0:
            guard let login = ClaudeLogin.read(output, now: now) else { return .failure(StateError(.noLogin)) }
            return .success(login)
        case 44:  // errSecItemNotFound
            return .failure(StateError(.noLogin))
        case 128, 51, 36:  // errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed
            return .failure(StateError(.refused))
        default:
            return .failure(StateError(.failed(status: Int(exitStatus))))
        }
    }

    struct StateError: Error {
        let state: State
        init(_ state: State) { self.state = state }
    }
}
