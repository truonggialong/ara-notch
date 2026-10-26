import AppKit
import Combine
import NotchShell
import SwiftUI
import TimerCore

/// State the timer page renders from.
@MainActor
final class TimerViewModel: ObservableObject {
    @Published var board = TimerBoard()
    /// The page is showing the choice of a length although countdowns are under way.
    @Published var isAdding = false
    /// Refreshed every second while a countdown runs, so views redraw.
    @Published var now = Date()

    /// What earlier countdowns were for.

    var onStart: ((Int) -> Void)?
    var onPause: ((Int) -> Void)?
    var onResume: ((Int) -> Void)?
    var onCancel: ((Int) -> Void)?
    var onExtend: ((Int, Int) -> Void)?

    /// True while the page shows the choice of a length.
    var isChoosing: Bool {
        board.entries.isEmpty || (isAdding && !board.isFull)
    }
}

/// Runs the countdowns: the notch page, the time beside the closed notch, and the alert at zero.
@MainActor
public final class TimerController {
    private static let activityID = "timer"
    /// The alert at zero has a place of its own: the time of the countdowns still running is
    /// re-presented every second and would otherwise take its place at once.
    private static let finishedActivityID = "timer.finished"

    private let settings: TimerSettings
    private let notch: NotchController
    private let viewModel = TimerViewModel()
    private var ticker: Timer?

    public init(settings: TimerSettings, notch: NotchController) {
        self.settings = settings
        self.notch = notch
        viewModel.onStart = { [weak self] seconds in self?.start(seconds: TimeInterval(seconds)) }
        viewModel.onPause = { [weak self] id in self?.pause(id) }
        viewModel.onResume = { [weak self] id in self?.resume(id) }
        viewModel.onCancel = { [weak self] id in self?.cancel(id) }
        viewModel.onExtend = { [weak self] id, seconds in self?.extend(id, by: TimeInterval(seconds)) }
    }

    /// The countdown ending soonest, as a tile of the overview page.
    public func makeOverviewTile() -> AnyView {
        AnyView(TimerWidget(model: viewModel, settings: settings) { [weak notch] in
            notch?.selectPage(id: "timer")
        })
    }


    public func makePage() -> NotchPage {
        var page = NotchPage(
            id: "timer", titleKey: "page.timer.title", symbolName: "timer", hue: .mint
        ) { [viewModel, settings] in
            TimerPageView(model: viewModel, settings: settings)
        }
        // From the keyboard: Return starts, pauses and resumes; ⌫ stops; the arrows set the length.
        // With several countdowns the keys act on the first of them.
        page.keyHandler = { [weak self] key, isTyping in
            guard let self else { return false }
            if self.viewModel.isChoosing {
                switch key {
                case .confirm:
                    self.start(seconds: TimeInterval(self.settings.seconds))
                // Up and down mean nothing in the one-line label field, so they set the length even
                // while it has the caret; left and right move the caret there.
                case .up, .right where !isTyping:
                    self.settings.turn(.minutes, by: 1)
                case .down, .left where !isTyping:
                    self.settings.turn(.minutes, by: -1)
                case .escape where self.viewModel.isAdding:
                    self.viewModel.isAdding = false
                default:
                    return false
                }
                return true
            }
            guard let entry = self.viewModel.board.entries.first else { return false }
            switch (entry.timer.phase, key) {
            case (.running, .confirm), (.running, .space):
                self.pause(entry.id)
            case (.paused, .confirm), (.paused, .space):
                self.resume(entry.id)
            case (.running, .delete), (.paused, .delete), (.finished, .confirm), (.finished, .delete):
                self.cancel(entry.id)
            default:
                return false
            }
            return true
        }
        return page
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(TimerSettingsSection(settings: settings))
    }

    /// Starts one more countdown, for what the label field says. With no room left it only beeps.
    public func start(seconds: TimeInterval) {
        guard viewModel.board.add(duration: seconds, label: settings.trimmedLabel, at: Date()) != nil else {
            NSSound.beep()
            return
        }
        // The next countdown is for something else.
        settings.label = ""
        viewModel.isAdding = false
        startTicking()
        refresh()
    }

    private func pause(_ id: Int) {
        viewModel.board.pause(id, at: Date())
        refresh()
    }

    private func resume(_ id: Int) {
        viewModel.board.resume(id, at: Date())
        startTicking()
        refresh()
    }

    private func cancel(_ id: Int) {
        viewModel.board.remove(id)
        refresh()
    }

    private func extend(_ id: Int, by seconds: TimeInterval) {
        viewModel.board.extend(id, by: seconds, at: Date())
        refresh()
    }

    // MARK: - Ticking

    /// The 1 Hz timer exists only while a countdown runs; an idle app has no timer at all.
    private func startTicking() {
        stopTicking()
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        ticker.tolerance = 0.05
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func refresh() {
        let now = Date()
        viewModel.now = now

        for entry in viewModel.board.tick(at: now) {
            finished(entry)
        }
        guard let soonest = viewModel.board.soonest(at: now) else {
            stopTicking()
            notch.dismissActivity(id: Self.activityID)
            return
        }

        // Re-presented every second with a short life: it refreshes the text, and if the
        // ticking ever stopped the activity would vanish instead of showing a stale time.
        let text = TimerFormat.clock(soonest.timer.remaining(at: now))
        let progress = soonest.timer.progress(at: now)
        notch.present(NotchLiveActivity(id: Self.activityID, priority: 1, duration: 2.5, pageID: "timer") {
            // A ring that fills as the time runs out.
            AraProgressRing(fraction: progress)
                .frame(width: 15, height: 15)
        } trailing: {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        })
    }

    private func finished(_ entry: TimerBoard.Entry) {
        let label = entry.label
        AraHaptics.play(.finish)
        notch.present(NotchLiveActivity(
            id: Self.finishedActivityID, priority: 3, duration: 6, pageID: "timer",
            sign: AraSign(
                tone: .attention, icon: .symbol("bell.fill"), mark: L10n.string("page.timer.title"),
                rows: [AraSign.Row(
                    L10n.string("timer.finished.short"), detail: label.isEmpty ? nil : label)])))
        if settings.soundEnabled {
            NSSound(named: "Glass")?.play()
        }
    }
}
