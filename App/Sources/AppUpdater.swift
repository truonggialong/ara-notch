import AppKit
import NotchCore
import NotchShell
import Sparkle
import SwiftUI

/// Looks for a newer version of the app among its releases, and downloads and installs it.
/// Sparkle does the work and shows its own windows; this is the app's handle on it.
@MainActor
// Sparkle calls its user-driver delegate on the main thread, where this class lives.
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// The newer version a check made by itself found, while it waits for the user to look
    /// at it; nil when there is none or its window is already on screen.
    @Published private(set) var waitingVersion: String?
    /// Called once when a check made by itself finds a newer version, with its number.
    var onFound: ((String) -> Void)?
    /// A feed to read in place of the one the app was built with, for trying an update
    /// before it is published.
    private let feedOverride: URL?

    /// Look for updates by itself, once a day.
    @Published var checksAutomatically = true {
        didSet {
            guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
            updater.automaticallyChecksForUpdates = checksAutomatically
        }
    }

    /// - Parameters:
    ///   - isTestRun: the app was started for an automated check, with data of its own.
    ///   - feedOverride: `--update-feed`, an https address or a server on this Mac.
    init(isTestRun: Bool, feedOverride: String?) {
        self.feedOverride = AppUpdatePolicy.feed(from: feedOverride)
        super.init()
        guard AppUpdatePolicy.runsUpdater(isTestRun: isTestRun, feedOverride: feedOverride) else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
    }

    /// False in a copy started for an automated check: there the controls say nothing can be done.
    var isAvailable: Bool {
        controller != nil
    }

    /// Asks now, and says what it found even when that is nothing new.
    func checkForUpdates() {
        guard let controller else { return }
        // The app has no Dock icon; its update window must still come to the front.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    /// Asks as soon as the updater is free: right after launch it is busy for a moment
    /// seeing whether an update was left half installed, and a check asked for then is dropped.
    func checkForUpdatesWhenReady(triesLeft: Int = 20) {
        guard let controller else { return }
        if controller.updater.canCheckForUpdates || triesLeft == 0 {
            checkForUpdates()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.checkForUpdatesWhenReady(triesLeft: triesLeft - 1)
            }
        }
    }

    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        feedOverride?.absoluteString
    }

    // MARK: - A newer version found while the app is out of the way

    // The app has no Dock icon and no window of its own most of the time, so a window that
    // appears by itself behind others may never be seen. A check made by itself therefore
    // says what it found beside the notch and on the About page; the update's own window
    // comes when the user asks for it there.

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Right after launch the update's window can have the user's eye at once; later it cannot.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        waitingVersion = version
        onFound?(version)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waitingVersion = nil
    }

    func standardUserDriverWillFinishUpdateSession() {
        waitingVersion = nil
    }

    /// What shows beside the closed notch when a newer version was found: a click on it
    /// opens the About page, where the update is one button away.
    static func reminder(forVersion version: String) -> NotchLiveActivity {
        NotchLiveActivity(
            id: "app.update", priority: 2, duration: 12, pageID: "about",
            sign: AraSign(
                icon: .symbol("arrow.down.circle"), mark: "AraNotch",
                rows: [AraSign.Row(L10n.string("update.found"), badge: .digits(version))]))
    }
}
