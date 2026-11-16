import AppKit
import FilesCore
import NotchShell
import SwiftUI

/// Follows the files downloading into the Downloads folder, as browsers publish their progress
/// (`Progress.addSubscriber`): while any is under way, a ring and the share done rest beside the
/// closed notch; when one finishes, a line says so. Nothing is read from the files themselves.
@MainActor
public final class DownloadsController {
    private let notch: NotchController
    private let folder: URL
    private var subscriber: Any?
    private var tally = DownloadTally()
    /// What is watched on each download's progress, by download.
    private var watchers: [String: [NSKeyValueObservation]] = [:]
    private static let restingID = "files.download"

    public init(notch: NotchController, folder: URL? = nil) {
        self.notch = notch
        self.folder = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    public func start() {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: folder) { [weak self] progress in
            let id = UUID().uuidString
            let name = (progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL)?.lastPathComponent ?? ""
            Task { @MainActor in self?.began(progress, id: id, name: name) }
            // Called when the download is no longer published: done, stopped or failed.
            return { [weak self] in
                let finished = progress.fractionCompleted >= 0.999 && !progress.isCancelled
                Task { @MainActor in self?.ended(id: id, name: name, finished: finished) }
            }
        }
    }

    public func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
    }

    private func began(_ progress: Progress, id: String, name: String) {
        tally.items[id] = .init(name: name, fraction: progress.totalUnitCount > 0 ? progress.fractionCompleted : nil)
        watchers[id] = [
            progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.totalUnitCount > 0 ? progress.fractionCompleted : nil
                Task { @MainActor in self?.update(id: id, fraction: fraction) }
            },
        ]
        refresh()
    }

    private var lastShown = -1
    private func update(id: String, fraction: Double?) {
        guard tally.items[id] != nil else { return }
        tally.items[id]?.fraction = fraction
        // Redrawn by the percent, not by every byte.
        let percent = Int(tally.fraction * 100)
        guard percent != lastShown else { return }
        refresh()
    }

    private func ended(id: String, name: String, finished: Bool) {
        watchers[id] = nil
        tally.items[id] = nil
        refresh()
        guard finished, !name.isEmpty else { return }
        notch.present(NotchLiveActivity(
            id: "files.downloaded", priority: 2, duration: 3,
            sign: AraSign(
                icon: .symbol("arrow.down.circle.fill"), mark: L10n.string("downloads.done"),
                rows: [AraSign.Row(name)])))
    }

    private func refresh() {
        guard !tally.isEmpty else {
            lastShown = -1
            notch.setRestingActivity(nil, id: Self.restingID)
            return
        }
        lastShown = Int(tally.fraction * 100)
        let fraction = tally.fraction
        let label = tally.label
        var activity = NotchLiveActivity(id: Self.restingID, priority: 1, duration: 0) {
            AraProgressRing(fraction: fraction)
                .frame(width: 14, height: 14)
                .foregroundStyle(AraPalette.tint(.sky).line)
                .accessibilityLabel(L10n.string("downloads.title"))
        } trailing: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .araRollingDigits(label, countsDown: false)
        }
        activity.peek = tally.items.values.map(\.name).sorted().joined(separator: ", ")
        notch.setRestingActivity(activity, id: Self.restingID)
    }
}
