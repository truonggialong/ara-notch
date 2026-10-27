import AppKit
import NotchShell
import SwiftUI

/// The Notes window, made once and shown again. Says when it closes, so the controller can stop refreshing and save.
@MainActor
final class NotesWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let model: NotesWindowModel
    var onClose: (() -> Void)?

    init(store: NotesStore, page: NotesPageModel) {
        let model = NotesWindowModel()
        self.model = model
        let hosting = NSHostingController(rootView: NotesWindowView(store: store, page: page, model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = L10n.string("notes.window.title")
        window.isReleasedWhenClosed = false
        // The title bar is part of the ground the cards lie on.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = AraPalette.nsGround
        window.contentMinSize = NSSize(width: NotesWindowView.minimumSize.width, height: NotesWindowView.minimumSize.height)
        window.setContentSize(NSSize(width: NotesWindowView.size.width, height: NotesWindowView.size.height))
        window.center()
        // Takes the frame saved last time, if there is one.
        window.setFrameAutosaveName("AraNotesWindow")
        self.window = window
        super.init()
        window.delegate = self
    }

    /// Keeps the window out of screenshots and recordings, or lets it be captured again.
    func setHiddenFromCapture(_ isHidden: Bool) {
        window.sharingType = isHidden ? .none : .readOnly
    }

    func show() {
        // An accessory app is not frontmost by default, so activate before showing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.deletingID = nil
        onClose?()
    }
}
