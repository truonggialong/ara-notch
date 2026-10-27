import AppKit
import NotchShell
import SwiftUI
import UniformTypeIdentifiers

/// What the page's toolbar acts on: the page's editor, through the same calls as the floating menu and the format
/// keys. The editor attaches itself when SwiftUI builds it.
@MainActor
final class NoteEditorHandle: ObservableObject {
    /// The styles the selection has, lit in the toolbar.
    @Published private(set) var active: Set<NoteFormat> = []
    private(set) weak var editor: NoteEditorCoordinator?
    /// Shows the picture chooser and hands back the files chosen (nil: cancelled). A window of its own rather than a
    /// sheet, since the notch's panel is no window for sheets. Tests replace it.
    var runOpenPanel: (NSOpenPanel, NSWindow?, @escaping ([URL]?) -> Void) -> Void = { panel, _, done in
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { response in done(response == .OK ? panel.urls : nil) }
    }

    /// The picture types a note keeps as they are.
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .gif, .tiff]

    func attach(_ editor: NoteEditorCoordinator) {
        self.editor = editor
        editor.handle = self
    }

    var isEditable: Bool { editor?.textView.isEditable ?? false }

    /// Reads the selection's styles again. Publishes only a change.
    func refresh() {
        let now = editor.map { editor in
            Set(NoteFormat.allCases.filter { $0 != .clear && editor.isActive($0) })
        } ?? []
        if active != now { active = now }
    }

    /// An inline style; `.link` opens the link field of the floating menu over the selection.
    @discardableResult
    func apply(_ format: NoteFormat) -> Bool {
        guard let editor, editor.textView.isEditable else { return false }
        return editor.perform(format)
    }

    /// Puts the caret in the editor and makes its window key. The editor of a page just shown may not be built yet,
    /// so this looks again a few times, a moment apart.
    func focus(attemptsLeft: Int = 10) {
        if let text = editor?.textView, let window = text.window, text.isEditable {
            window.makeKey()
            window.makeFirstResponder(text)
            return
        }
        guard attemptsLeft > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.focus(attemptsLeft: attemptsLeft - 1) }
        }
    }

    /// A paragraph kind for the paragraphs of the selection.
    @discardableResult
    func apply(_ block: BlockFormat) -> Bool {
        guard let editor, editor.textView.isEditable else { return false }
        return editor.apply(block)
    }

    /// Puts a picture file at the selection, the way pasting it would: kept by the store under an attachment index,
    /// never as a bare attachment.
    @discardableResult
    func insertImage(from url: URL) -> Bool {
        guard let editor, editor.textView.isEditable else { return false }
        let board = NSPasteboard(name: NSPasteboard.Name("AraNotch.notes.insertImage.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        guard board.writeObjects([url as NSURL]) else { return false }
        return editor.textView.insert(from: board)
    }

    /// Asks for pictures and puts them at the selection. `onChoosing` is told true while the chooser is up, and
    /// false once it is gone and the caret is back in the editor.
    func chooseImages(onChoosing: @escaping (Bool) -> Void = { _ in }) {
        guard let editor, editor.textView.isEditable else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.imageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        onChoosing(true)
        runOpenPanel(panel, editor.textView.window) { [weak self] urls in
            MainActor.assumeIsolated {
                if let self {
                    for url in urls ?? [] where !self.insertImage(from: url) { NSSound.beep() }
                    if let text = self.editor?.textView, let window = text.window {
                        window.makeKey()
                        window.makeFirstResponder(text)
                    }
                }
                onChoosing(false)
            }
        }
    }
}

/// The fixed toolbar over the page's editor: the floating menu's styles, the paragraph kinds, a bulleted list,
/// a code block and a picture. Greyed out while the note cannot be edited.
struct FormatToolbar: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var handle: NoteEditorHandle
    let isEnabled: Bool
    var onChoosingImages: (Bool) -> Void = { _ in }

    private static let styles: [(NoteFormat, String, String)] = [
        (.bold, "bold", "notes.format.bold"), (.italic, "italic", "notes.format.italic"),
        (.underline, "underline", "notes.format.underline"), (.strikethrough, "strikethrough", "notes.format.strikethrough"),
        (.monospaced, "chevron.left.forwardslash.chevron.right", "notes.format.monospaced"),
        (.link, "link", "notes.format.link"),
    ]

    private static let paragraphKinds: [(BlockFormat, String)] = [
        (.title, "notes.toolbar.title"), (.heading, "notes.toolbar.heading"),
        (.subheading, "notes.toolbar.subheading"), (.body, "notes.toolbar.body"),
    ]

    var body: some View {
        HStack(spacing: 1 * ui) {
            ForEach(Self.styles, id: \.1) { format, symbol, key in
                button(symbol, key, isLit: handle.active.contains(format)) { handle.apply(format) }
            }
            divider
            Menu {
                ForEach(Self.paragraphKinds, id: \.1) { block, key in
                    Button(L10n.string(key)) { handle.apply(block) }
                }
            } label: {
                HStack(spacing: 3 * ui) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 11 * ui, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7 * ui, weight: .bold))
                }
                .foregroundStyle(AraPalette.ground)
                .padding(.horizontal, 6 * ui)
                .frame(height: 24 * ui)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(L10n.string("notes.toolbar.paragraph"))
            .accessibilityLabel(L10n.string("notes.toolbar.paragraph"))
            button("list.bullet", "notes.toolbar.bulletList", isLit: false) { handle.apply(.bulletList) }
            button("curlybraces", "notes.toolbar.codeBlock", isLit: false) { handle.apply(.codeBlock) }
            divider
            button("photo", "notes.toolbar.image", isLit: false) { handle.chooseImages(onChoosing: onChoosingImages) }
        }
        .padding(.horizontal, 5 * ui)
        .frame(height: 28 * ui)
        .background(Capsule().fill(AraPalette.onGround))
        .fixedSize()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var divider: some View {
        Rectangle()
            .fill(AraPalette.ground.opacity(0.25))
            .frame(width: 1, height: 14 * ui)
            .padding(.horizontal, 3 * ui)
    }

    private func button(_ symbol: String, _ key: String, isLit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11 * ui, weight: .semibold))
                .foregroundStyle(isLit ? AraPalette.accent : AraPalette.ground)
                .frame(width: 24 * ui, height: 24 * ui)
                .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle())
        .help(L10n.string(key))
        .accessibilityLabel(L10n.string(key))
    }
}
