import AgentCore
import Foundation
import Security

/// Asks the Claude account for its rate limits every few minutes, as Claude Code's `/usage`
/// does, with the sign-in Claude Code keeps in the keychain. This works whatever runs Claude
/// Code, the desktop app's Code tab included, which never runs the status line.
///
/// The access token is read from the keychain only when there is none in memory or it was
/// refused, and is never written anywhere, logged or renewed: Claude Code renews it itself.
@MainActor
final class ClaudeAccountReader {
    enum State: Equatable {
        case off
        case reading
        case read(at: Date)
        /// No Claude Code sign-in in the keychain.
        case noLogin
        /// The user did not allow the keychain read.
        case refused
        /// The sign-in is out of date; Claude Code renews it when it next runs.
        case expired
        case failed(status: Int)
    }

    var onUsage: ((AgentUsage) -> Void)?
    var onState: ((State) -> Void)?

    /// Five minutes, like a glance at `/usage` now and then; the limits do not move faster.
    static let interval: TimeInterval = 300

    private var timer: Timer?
    private var token: String?
    private var isReading = false

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        read()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        token = nil
        onState?(.off)
    }

    func read() {
        guard timer != nil, !isReading else { return }
        isReading = true
        onState?(.reading)
        let known = token
        Task.detached(priority: .utility) {
            let outcome = await Self.fetch(knownToken: known)
            await MainActor.run { [weak self] in self?.finish(outcome) }
        }
    }

    private func finish(_ outcome: Outcome) {
        isReading = false
        guard timer != nil else { return }
        switch outcome {
        case .usage(let usage, let token):
            self.token = token
            onUsage?(usage)
            onState?(.read(at: usage.updatedAt))
        case .state(let state):
            token = nil
            onState?(state)
        }
    }

    private enum Outcome: Sendable {
        case usage(AgentUsage, token: String)
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
            return .usage(usage, token: token)
        case 401:
            // A token kept from an earlier read may have been renewed by Claude Code since.
            return knownToken == nil ? .state(.expired) : await fetch(knownToken: nil)
        default:
            return .state(.failed(status: status))
        }
    }

    nonisolated private static func readLogin() -> Result<ClaudeLogin, StateError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ClaudeLogin.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let login = ClaudeLogin.read(data, now: Date()) else {
                return .failure(StateError(.noLogin))
            }
            return .success(login)
        case errSecItemNotFound:
            return .failure(StateError(.noLogin))
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            return .failure(StateError(.refused))
        default:
            return .failure(StateError(.failed(status: Int(status))))
        }
    }

    private struct StateError: Error {
        let state: State
        init(_ state: State) { self.state = state }
    }
}
