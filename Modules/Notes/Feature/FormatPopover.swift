import AppKit
import Combine
import NotchShell
import SwiftUI

/// What the format menu shows: which styles the selection has, and the link being typed.
@MainActor
final class FormatPopoverModel: ObservableObject {
    @Published var active: Set<NoteFormat> = []
    @Published var isEditingLink = false
    @Published var linkText = ""
}

/// The small menu of styles that floats above selected text, as in Telegram: Bold, Italic, Underline,
/// Strikethrough, Monospace, Link, Clear. It never takes the keyboard, except while a link is typed in it.
@MainActor
final class FormatPopover {
    private weak var editor: NoteEditorCoordinator?
    let model = FormatPopoverModel()
    private var panel: FormatPanel?
    private var windowObservers: [NSObjectProtocol] = []
    private weak var watchedWindow: NSWindow?

    var isEditingLink: Bool { model.isEditingLink }

    init(editor: NoteEditorCoordinator) {
        self.editor = editor
    }

    // MARK: Showing

    /// Shows the menu over a selection, or hides it when there is none.
    func selectionChanged() {
        guard !model.isEditingLink else { return }
        guard let text = editor?.textView, let window = text.window, window.isKeyWindow, text.isEditable,
              text.selectedRange().length > 0 else {
            hide()
            return
        }
        refresh()
        show(over: text, in: window)
    }

    /// Updates which buttons are lit.
    func refresh() {
        guard let editor else { return }
        model.active = Set(NoteFormat.allCases.filter { $0 != .clear && editor.isActive($0) })
    }

    func hide() {
        endLinkEditing(restoreFocus: false)
        panel?.orderOut(nil)
    }

    private func show(over text: NSTextView, in window: NSWindow) {
        let panel = self.panel ?? makePanel()
        watch(window)
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        let size = panel.contentView?.fittingSize ?? NSSize(width: 240, height: 34)
        let selection = text.firstRect(forCharacterRange: text.selectedRange(), actualRange: nil)
        let screen = (window.screen ?? NSScreen.main)?.frame ?? .infinite
        var origin = NSPoint(x: selection.midX - size.width / 2, y: selection.maxY + 6)
        if origin.y + size.height > screen.maxY { origin.y = selection.minY - 6 - size.height }   // no room above
        origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    /// Closes the panel and stops watching windows: the editor is going away.
    func tearDown() {
        hide()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        watchedWindow = nil
        panel?.contentView = nil
        panel?.close()
        panel = nil
    }

    func makePanel() -> FormatPanel {
        let panel = FormatPanel()
        panel.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: FormatMenuView(model: model, popover: self))
        host.setFrameSize(host.fittingSize)
        panel.contentView = host
        self.panel = panel
        return panel
    }

    /// Hides the menu when the editor's window stops being the key one, but not for the menu's own link field.
    private func watch(_ window: NSWindow) {
        guard watchedWindow !== window else { return }
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        watchedWindow = window
        windowObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) {
                [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !(NSApp.keyWindow === self.panel) else { return }
                    self.hide()
                }
            },
        ]
    }

    // MARK: Actions

    func apply(_ format: NoteFormat) {
        guard let editor else { return }
        if format == .link {
            beginLink()
            return
        }
        editor.apply(format, link: nil)
        refresh()
    }

    /// Opens the link field in the menu, filled with the selection's link or a link on the clipboard.
    func beginLink() {
        guard let editor, editor.textView.selectedRange().length > 0 else {
            NSSound.beep()
            return
        }
        let text = editor.textView
        if panel?.isVisible != true, let window = text.window {
            refresh()
            show(over: text, in: window)
        }
        let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clipboardLink = clipboard.flatMap { URL(string: $0) }.flatMap { $0.scheme == nil ? nil : $0 }
        model.linkText = (editor.selectedLink ?? clipboardLink)?.absoluteString ?? ""
        model.isEditingLink = true
        editor.linkEditingChanged(true)
        resize()
        guard let panel else { return }
        panel.allowsKey = true
        panel.makeKey()
        focusField(in: panel, attemptsLeft: 5)
    }

    func confirmLink() {
        guard let editor else { return }
        let typed = model.linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = typed.isEmpty ? nil : Self.link(from: typed)
        if !typed.isEmpty, url == nil {
            NSSound.beep()
            return
        }
        endLinkEditing(restoreFocus: true)
        editor.apply(.link, link: url)
        refresh()
    }

    func cancelLink() {
        endLinkEditing(restoreFocus: true)
    }

    /// "example.com" gets https; anything with a scheme is taken as it is.
    static func link(from text: String) -> URL? {
        if let url = URL(string: text), url.scheme != nil { return url }
        guard !text.contains(" "), text.contains(".") else { return nil }
        return URL(string: "https://" + text)
    }

    private func endLinkEditing(restoreFocus: Bool) {
        guard model.isEditingLink else { return }
        model.isEditingLink = false
        panel?.allowsKey = false
        resize()
        if restoreFocus, let text = editor?.textView, let window = text.window {
            window.makeKey()
            window.makeFirstResponder(text)
        }
        editor?.linkEditingChanged(false)
    }

    private func resize() {
        guard let panel, let content = panel.contentView else { return }
        let size = content.fittingSize
        var frame = panel.frame
        frame.origin.x += (frame.width - size.width) / 2
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func focusField(in panel: NSPanel, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak panel] in
            guard let panel, let content = panel.contentView else { return }
            if let field = Self.firstTextField(in: content) {
                panel.makeFirstResponder(field)
            } else if attemptsLeft > 1 {
                self?.focusField(in: panel, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.isEditable { return field }
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }
}

/// A borderless panel that does not activate the app and takes the keyboard only for the link field.
final class FormatPanel: NSPanel {
    var allowsKey = false

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 240, height: 34), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        hidesOnDeactivate = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}

/// The menu's face: a black pill of buttons; the styles the selection has are lit in the accent colour.
struct FormatMenuView: View {
    @ObservedObject var model: FormatPopoverModel
    /// Weak: the popover owns the panel this view is in.
    weak var popover: FormatPopover?

    private static let buttons: [(NoteFormat, String, String)] = [
        (.bold, "bold", "notes.format.bold"), (.italic, "italic", "notes.format.italic"),
        (.underline, "underline", "notes.format.underline"), (.strikethrough, "strikethrough", "notes.format.strikethrough"),
        (.monospaced, "chevron.left.forwardslash.chevron.right", "notes.format.monospaced"),
        (.link, "link", "notes.format.link"), (.clear, "textformat", "notes.format.clear"),
    ]

    var body: some View {
        Group {
            if model.isEditingLink { linkField } else { buttonRow }
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(Capsule().fill(AraPalette.onGround))
        .fixedSize()
    }

    private var buttonRow: some View {
        HStack(spacing: 2) {
            ForEach(Self.buttons, id: \.1) { format, symbol, key in
                Button {
                    popover?.apply(format)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.active.contains(format) ? AraPalette.accent : AraPalette.ground)
                        .frame(width: 28, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AraPressStyle())
                .help(L10n.string(key))
                .accessibilityLabel(L10n.string(key))
            }
        }
    }

    private var linkField: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AraPalette.ground)
            TextField(L10n.string("notes.format.link.placeholder"), text: $model.linkText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(AraPalette.ground)
                .frame(width: 200)
                .onSubmit { popover?.confirmLink() }
                .onExitCommand { popover?.cancelLink() }
            Button { popover?.confirmLink() } label: {
                AraIcon.confirm.image.font(.system(size: 11, weight: .bold)).foregroundStyle(AraPalette.accent)
            }
            .buttonStyle(AraPressStyle())
            .help(L10n.string("notes.format.link.save"))
            Button { popover?.cancelLink() } label: {
                AraIcon.close.image.font(.system(size: 11, weight: .bold)).foregroundStyle(AraPalette.ground)
            }
            .buttonStyle(AraPressStyle())
            .help(L10n.string("notes.format.link.cancel"))
        }
        .padding(.horizontal, 6)
    }
}
