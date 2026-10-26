import AppKit
import Quartz

/// Shows files in the system's Quick Look panel, the one the space bar opens in Finder.
@MainActor
public final class AraQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = AraQuickLook()

    private var urls: [URL] = []

    public var isShowing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Opens the panel on these files, or swaps what an open panel shows.
    public func show(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty, let panel = QLPreviewPanel.shared() else {
            NSSound.beep()
            return
        }
        self.urls = existing
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        if !panel.isVisible {
            // The app runs without a Dock icon; it has to come forward for the panel to show.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens the panel, or closes it when it is already showing: what the space bar does.
    public func toggle(_ urls: [URL]) {
        if isShowing {
            close()
        } else {
            show(urls)
        }
    }

    public func close() {
        guard isShowing else { return }
        QLPreviewPanel.shared().orderOut(nil)
    }

    public nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    public nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let url: URL? = MainActor.assumeIsolated { urls.indices.contains(index) ? urls[index] : nil }
        return url.map { $0 as NSURL }
    }
}
