import AgentFeature
import AppKit
import NotchCore
import NotchShell
import ServiceManagement

/// Takes AraNotch off this Mac, after asking: its hooks and status line come out of Claude
/// Code's settings (backed up first), it no longer opens at login, its caches go and, when the
/// user ticks it, its clipboard history, agent data and settings too; then the app goes to the
/// Trash and quits.
@MainActor
struct Uninstaller {
    let agents: AgentController
    /// A folder standing in for the home folder, for trying this out; see `--uninstall-home`.
    let testHome: URL?

    func confirmAndRun() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("uninstall.title")
        alert.informativeText = L10n.string("uninstall.message")
        let removesData = NSButton(checkboxWithTitle: L10n.string("uninstall.removeData"), target: nil, action: nil)
        removesData.state = .on
        alert.accessoryView = removesData
        let confirm = alert.addButton(withTitle: L10n.string("uninstall.confirm"))
        confirm.hasDestructiveAction = true
        alert.addButton(withTitle: L10n.string("uninstall.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(removesData: removesData.state == .on)
    }

    private func run(removesData: Bool) {
        let isTrial = testHome != nil
        let plan = UninstallPlan(
            home: testHome ?? FileManager.default.homeDirectoryForCurrentUser,
            bundleID: Bundle.main.bundleIdentifier ?? "com.aranotch.app", removesData: removesData)
        var problems: [String] = []

        do {
            try agents.removeFromClaudeCode(settingsFile: plan.claudeSettings)
        } catch {
            problems.append(String(describing: error))
        }
        if !isTrial, SMAppService.mainApp.status == .enabled {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                problems.append(error.localizedDescription)
            }
        }
        for url in plan.removals where FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if plan.removesSettings, !isTrial {
            UserDefaults.standard.removePersistentDomain(forName: plan.bundleID)
        }

        if !problems.isEmpty {
            let alert = NSAlert()
            alert.messageText = L10n.string("uninstall.failed")
            alert.informativeText = problems.joined(separator: "\n")
            alert.runModal()
        }
        if isTrial {
            NSApp.terminate(nil)
            return
        }
        // The app goes last: the Trash keeps it, so this can still be taken back.
        // Of no actor: the system may call it on any queue.
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { @Sendable _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
