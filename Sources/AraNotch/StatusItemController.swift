import AppKit
import ClipboardCore
import NotchShell

/// The menu bar icon and its menu.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let pauseItem: NSMenuItem
    private let resumeItem: NSMenuItem
    private let recordingState: () -> RecordingState
    private let onOpenLibrary: () -> Void
    private let onOpenSettings: () -> Void
    private let onCapture: () -> Void
    private let onNewNote: () -> Void
    /// Given how long to pause recording for, or nil to resume it.
    private let onPause: (CapturePause?) -> Void
    private let onScrollCapture: () -> Void
    private let onCaptureText: () -> Void
    private let onPickColor: () -> Void
    private let onCheckForUpdates: () -> Void

    init(
        onOpenLibrary: @escaping () -> Void, onNewNote: @escaping () -> Void,
        onPause: @escaping (CapturePause?) -> Void, recordingState: @escaping () -> RecordingState,
        onCapture: @escaping () -> Void, onScrollCapture: @escaping () -> Void,
        onCaptureText: @escaping () -> Void, onPickColor: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void, onCheckForUpdates: @escaping () -> Void
    ) {
        self.onCheckForUpdates = onCheckForUpdates
        self.onCaptureText = onCaptureText
        self.onPickColor = onPickColor
        self.onCapture = onCapture
        self.onNewNote = onNewNote
        self.onPause = onPause
        self.recordingState = recordingState
        pauseItem = NSMenuItem(title: L10n.string("menu.pause"), action: nil, keyEquivalent: "")
        resumeItem = NSMenuItem(title: L10n.string("menu.resume"), action: #selector(resumeRecording), keyEquivalent: "")
        self.onScrollCapture = onScrollCapture
        self.onOpenLibrary = onOpenLibrary
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            // The app's own mark: a screen with its notch.
            let image = AraGlyph.mark.image(size: 18)
            image.accessibilityDescription = "AraNotch"
            button.image = image
        }

        let menu = NSMenu()
        let libraryItem = NSMenuItem(
            title: L10n.string("menu.library"), action: #selector(openLibrary), keyEquivalent: "l")
        libraryItem.target = self
        menu.addItem(libraryItem)
        let noteItem = NSMenuItem(title: L10n.string("menu.newNote"), action: #selector(newNote), keyEquivalent: "n")
        noteItem.target = self
        menu.addItem(noteItem)
        let pauseMenu = NSMenu()
        // Resume is only offered while there is a pause to end.
        pauseMenu.autoenablesItems = false
        for pause in CapturePause.allCases {
            let item = NSMenuItem(
                title: L10n.string("settings.clipboard.pause.\(pause.rawValue)"), action: #selector(pauseRecording(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = pause.rawValue
            pauseMenu.addItem(item)
        }
        pauseMenu.addItem(.separator())
        resumeItem.target = self
        pauseMenu.addItem(resumeItem)
        pauseItem.submenu = pauseMenu
        menu.addItem(pauseItem)
        menu.addItem(.separator())
        let captureItem = NSMenuItem(title: L10n.string("menu.capture"), action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        let scrollItem = NSMenuItem(
            title: L10n.string("menu.capture.scroll"), action: #selector(scrollCapture), keyEquivalent: "")
        scrollItem.target = self
        menu.addItem(scrollItem)
        let textItem = NSMenuItem(title: L10n.string("menu.capture.text"), action: #selector(captureText), keyEquivalent: "")
        textItem.target = self
        menu.addItem(textItem)
        let colorItem = NSMenuItem(title: L10n.string("menu.capture.color"), action: #selector(pickColor), keyEquivalent: "")
        colorItem.target = self
        menu.addItem(colorItem)
        let settingsItem = NSMenuItem(
            title: L10n.string("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let updateItem = NSMenuItem(
            title: L10n.string("menu.checkForUpdates"), action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: L10n.string("menu.quit"), action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        // The same icon an action has in the app's windows marks it here.
        let icons: [(NSMenuItem, AraIcon)] = [
            (libraryItem, .clipboard), (noteItem, .newNote), (pauseItem, .paused), (captureItem, .captureRegion),
            (scrollItem, .captureScroll), (textItem, .readText), (colorItem, .pickColor), (settingsItem, .settings),
            (updateItem, .reset),
        ]
        for (item, icon) in icons {
            item.image = NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil)
        }
        menu.delegate = self
        statusItem.menu = menu
    }

    private static let pauseEndFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// The menu says whether recording is paused, and until when, each time it opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let state = recordingState()
        switch state {
        case .recording:
            pauseItem.title = L10n.string("menu.pause")
        case .paused:
            pauseItem.title = L10n.string("menu.paused")
        case .pausedUntil(let end):
            pauseItem.title = String(format: L10n.string("menu.pausedUntil"), Self.pauseEndFormatter.string(from: end))
        }
        resumeItem.isEnabled = state.isPaused
    }

    @objc private func openLibrary() {
        onOpenLibrary()
    }

    @objc private func capture() {
        onCapture()
    }

    @objc private func newNote() {
        onNewNote()
    }

    @objc private func pauseRecording(_ sender: NSMenuItem) {
        if let pause = (sender.representedObject as? String).flatMap(CapturePause.init) {
            onPause(pause)
        }
    }

    @objc private func resumeRecording() {
        onPause(nil)
    }

    @objc private func captureText() {
        onCaptureText()
    }

    @objc private func pickColor() {
        onPickColor()
    }

    @objc private func scrollCapture() {
        onScrollCapture()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
