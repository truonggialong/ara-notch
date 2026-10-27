import AppKit
import NotchShell
import SwiftUI
import UniformTypeIdentifiers

/// What the Notes window's toolbar acts on: the window's editor, through the same calls as the floating menu
/// and the format keys. The editor attaches itself when SwiftUI builds it.
@MainActor
final class NoteEditorHandle: ObservableObject {
    /// The styles the selection has, lit in the toolbar.
    @Published private(set) var active: Set<NoteFormat> = []
    private(set) weak var editor: NoteEditorCoordinator?

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

    /// Asks for pictures in a sheet on the editor's window and puts them at the selection.
    func chooseImages() {
        guard let editor, editor.textView.isEditable, let window = editor.textView.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.imageTypes
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            MainActor.assumeIsolated {
                guard let self else { return }
                for url in urls where !self.insertImage(from: url) { NSSound.beep() }
                if let text = self.editor?.textView { text.window?.makeFirstResponder(text) }
            }
        }
    }
}

/// The fixed toolbar over the window's editor: the floating menu's styles, the paragraph kinds, a bulleted list,
/// a code block and a picture. Greyed out while the note cannot be edited.
struct FormatToolbar: View {
    @ObservedObject var handle: NoteEditorHandle
    let isEnabled: Bool

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
        HStack(spacing: 2) {
            ForEach(Self.styles, id: \.1) { format, symbol, key in
                button(symbol, key, isLit: handle.active.contains(format)) { handle.apply(format) }
            }
            divider
            Menu {
                ForEach(Self.paragraphKinds, id: \.1) { block, key in
                    Button(L10n.string(key)) { handle.apply(block) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.string("notes.toolbar.paragraph"))
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(AraPalette.ground)
                .padding(.horizontal, 8)
                .frame(height: 26)
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
            button("photo", "notes.toolbar.image", isLit: false) { handle.chooseImages() }
        }
        .padding(.horizontal, 6)
        .frame(height: 32)
        .background(Capsule().fill(AraPalette.onGround))
        .fixedSize()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var divider: some View {
        Rectangle()
            .fill(AraPalette.ground.opacity(0.25))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func button(_ symbol: String, _ key: String, isLit: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isLit ? AraPalette.accent : AraPalette.ground)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle())
        .help(L10n.string(key))
        .accessibilityLabel(L10n.string(key))
    }
}
