import AppKit
import ClipboardCore
import NotchShell
import SwiftUI

/// State of the window that edits one clip.
@MainActor
final class ClipEditorModel: ObservableObject {
    /// The clip being edited; nil when a new note is being written.
    let item: ClipItem?
    @Published var title: String
    @Published var text: String
    /// Why the last save did not go through.
    @Published var message = ""

    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    init(item: ClipItem?) {
        self.item = item
        title = item?.title ?? ""
        text = item?.text ?? ""
    }

    /// A new note always has text to write; an existing clip only when it is a text clip.
    var showsText: Bool { item?.isTextEditable ?? true }
}

/// A title for any clip; for text, links and colours also the text itself. One card
/// on the theme's ground.
struct ClipEditorView: View {
    @ObservedObject var model: ClipEditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.string("clipboard.edit.title.placeholder"), text: $model.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .araSurface(Capsule(), level: .raised)
            if model.showsText {
                TextEditor(text: $model.text)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(minHeight: 160)
                    .araSurface(RoundedRectangle(cornerRadius: AraTheme.rowRadius, style: .continuous), level: .raised)
            }
            HStack(spacing: 8) {
                Text(model.message)
                    .font(.caption)
                    .foregroundStyle(AraPalette.warning)
                Spacer()
                AraPillButton(L10n.string("settings.cancel")) { model.onCancel?() }
                    .keyboardShortcut(.cancelAction)
                AraPillButton(L10n.string("clipboard.edit.save"), icon: .confirm, isProminent: true) { model.onSave?() }
                    .keyboardShortcut(.defaultAction)
                    // Return adds a line while the text is being written, so ⌘Return saves from there.
                    .background(
                        Button("") { model.onSave?() }
                            .keyboardShortcut(.return, modifiers: .command)
                            .opacity(0)
                            .accessibilityHidden(true))
            }
        }
        .padding(14)
        .araCard(radius: 16)
        .padding(12)
        .frame(width: 484)
        .background(AraPalette.ground)
    }
}

/// Opens an editor window per clip and keeps it alive until it closes.
@MainActor
final class ClipEditorWindows {
    private var windows: [Int64: NSWindow] = [:]
    private var observers: [Int64: NSObjectProtocol] = [:]

    /// - Parameter save: given the edited title and text; returns nil when saved, or the
    ///   message to show when not.
    func open(_ item: ClipItem, save: @escaping @MainActor (_ title: String, _ text: String) -> String?) {
        open(id: item.id, item: item, windowTitleKey: "clipboard.edit.window", save: save)
    }

    private func open(
        id: Int64, item: ClipItem?, windowTitleKey: String,
        save: @escaping @MainActor (_ title: String, _ text: String) -> String?
    ) {
        if let window = windows[id] {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = ClipEditorModel(item: item)
        let window = Self.makeWindow(model: model, title: L10n.string(windowTitleKey))
        model.onCancel = { [weak window] in window?.close() }
        model.onSave = { [weak window, weak model] in
            guard let model else { return }
            if let message = save(model.title, model.text) {
                model.message = message
            } else {
                window?.close()
            }
        }
        observers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.windows[id] = nil
                if let observer = self.observers.removeValue(forKey: id) {
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
        windows[id] = window
        // An accessory app is not frontmost by default, so activate before showing.
        NSApp.activate(ignoringOtherApps: true)
        Self.focusFirstField(in: window, prefersText: model.showsText)
        window.makeKeyAndOrderFront(nil)
        // Once more after the window is up: on becoming key it hands the keys to its first field.
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible else { return }
            Self.focusFirstField(in: window, prefersText: model.showsText)
        }
    }

    /// The editor's window at its full size, in the middle of the screen. A hosting window has
    /// no size before its first layout, and centring that puts its corner in the middle.
    static func makeWindow(model: ClipEditorModel, title: String) -> NSWindow {
        let host = NSHostingController(rootView: ClipEditorView(model: model))
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable]
        window.title = title
        window.isReleasedWhenClosed = false
        window.setContentSize(host.view.fittingSize)
        window.center()
        return window
    }

    /// Puts the cursor where typing starts: in the text when there is text to write, else in
    /// the title. Without this the window opens with no field taking the keys.
    static func focusFirstField(in window: NSWindow, prefersText: Bool) {
        window.layoutIfNeeded()
        guard let content = window.contentView else { return }
        let text = prefersText ? firstDescendant(of: content) { $0 is NSTextView } : nil
        if let field = text ?? firstDescendant(of: content, where: { ($0 as? NSTextField)?.isEditable == true }) {
            window.initialFirstResponder = field
            window.makeFirstResponder(field)
        }
        // With a mouse attached macOS keeps a scroll bar's grey track beside the text even when
        // there is nothing to scroll; the bar shows while scrolling instead.
        if let scroll = firstDescendant(of: content, where: { $0 is NSScrollView }) as? NSScrollView {
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }
    }

    private static func firstDescendant(of view: NSView, where matches: (NSView) -> Bool) -> NSView? {
        for subview in view.subviews {
            if matches(subview) { return subview }
            if let found = firstDescendant(of: subview, where: matches) { return found }
        }
        return nil
    }
}
