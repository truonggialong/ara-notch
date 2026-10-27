import AppKit
import UniformTypeIdentifiers

/// What the text view asks of the editor that owns it.
@MainActor
protocol NoteTextViewHost: AnyObject {
    /// Applies a format command to the selection; false when it could not (a read-only note).
    func perform(_ format: NoteFormat) -> Bool
    /// Keeps an image the user put in the note and returns its text (an image line), or nil to refuse it.
    func imageLine(for data: Data, fileExtension: String) -> NSAttributedString?
    /// The range a paste or drop over `range` really replaces: widened so no list mark is cut in two.
    func rangeForReplacing(_ range: NSRange) -> NSRange
    func focusChanged(_ isFocused: Bool)
}

/// The editor's text view: format keys, and paste and drop that take only plain text and images,
/// so nothing enters the text that a note cannot be written back from.
final class NoteTextView: NSTextView {
    weak var host: NoteTextViewHost?

    /// The image types a note keeps as they are; any other picture is turned into PNG.
    private static let keptImageTypes: [(NSPasteboard.PasteboardType, String)] = [
        (.png, "png"), (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (NSPasteboard.PasteboardType(UTType.gif.identifier), "gif"), (.tiff, "tiff"),
    ]
    private static let keptExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "tiff", "tif"]

    // MARK: Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Only for the view that has the keyboard (a window walks every view with these keys).
        if let window, window.firstResponder !== self { return super.performKeyEquivalent(with: event) }
        guard let format = Self.format(for: event) else { return super.performKeyEquivalent(with: event) }
        guard isEditable, let host else { return false }
        if !host.perform(format) { NSSound.beep() }
        return true
    }

    /// ⌘B ⌘I ⌘U ⌘⇧X ⌘⇧M ⌘K.
    static func format(for event: NSEvent) -> NoteFormat? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return nil }
        switch (flags, key) {
        case ([.command], "b"): return .bold
        case ([.command], "i"): return .italic
        case ([.command], "u"): return .underline
        case ([.command], "k"): return .link
        case ([.command, .shift], "x"): return .strikethrough
        case ([.command, .shift], "m"): return .monospaced
        default: return nil
        }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { host?.focusChanged(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { host?.focusChanged(false) }
        return resigned
    }

    // MARK: Paste and drop

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string, .fileURL] + Self.keptImageTypes.map(\.0)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] { readablePasteboardTypes }

    override func paste(_ sender: Any?) { pasteFromGeneral() }
    override func pasteAsPlainText(_ sender: Any?) { pasteFromGeneral() }
    override func pasteAsRichText(_ sender: Any?) { pasteFromGeneral() }

    private func pasteFromGeneral() {
        if !insert(from: .general) { NSSound.beep() }
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        insert(from: pboard)
    }

    override func readSelection(from pboard: NSPasteboard) -> Bool { insert(from: pboard) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Text moved within the note would travel as rich text that loses what each line is.
        if sender.draggingSource as? NoteTextView === self || !isEditable { return [] }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingSource as? NoteTextView === self || !isEditable { return [] }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isEditable, sender.draggingSource as? NoteTextView !== self else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: index, length: 0))
        return insert(from: sender.draggingPasteboard)
    }

    /// Puts the pasteboard's plain text and pictures in place of the selection. Returns false when nothing was taken.
    @discardableResult
    func insert(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable, let storage = textStorage else { return false }
        let pieces = (pasteboard.pasteboardItems ?? []).compactMap(piece(of:))
        guard !pieces.isEmpty else { return false }
        // Widened here, not by the delegate: the delegate's widened replace is plain text and would drop pictures.
        let range = host?.rangeForReplacing(selectedRange()) ?? selectedRange()
        let insertion = NSMutableAttributedString()
        let typing = NoteAttributedText.cleanTypingAttributes(typingAttributes)
        var refused = false
        for piece in pieces {
            switch piece {
            case .text(let string):
                // A lone U+FFFC would be written as text, not as a picture.
                let plain = string.replacingOccurrences(of: "\u{FFFC}", with: "")
                if !plain.isEmpty { insertion.append(NSAttributedString(string: plain, attributes: typing)) }
            case .image(let data, let ext):
                guard let line = host?.imageLine(for: data, fileExtension: ext) else {
                    refused = true
                    continue
                }
                // A picture is a line of its own.
                let before = (storage.string as NSString).substring(to: range.location) + insertion.string
                if !before.isEmpty, !before.hasSuffix("\n") {
                    insertion.append(NSAttributedString(string: "\n", attributes: typing))
                }
                insertion.append(line)
            }
        }
        if refused { NSSound.beep() }
        guard insertion.length > 0, shouldChangeText(in: range, replacementString: insertion.string) else { return false }
        storage.replaceCharacters(in: range, with: insertion)
        setSelectedRange(NSRange(location: range.location + insertion.length, length: 0))
        didChangeText()
        return true
    }

    private enum Piece {
        case text(String)
        case image(Data, String)
    }

    /// One pasteboard item as text or an image. Text wins over a picture of it (as Word copies both).
    private func piece(of item: NSPasteboardItem) -> Piece? {
        if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString), url.isFileURL {
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                  let data = try? Data(contentsOf: url) else { return nil }
            let ext = url.pathExtension.lowercased()
            if Self.keptExtensions.contains(ext) { return .image(data, ext) }
            return Self.png(from: data).map { .image($0, "png") }
        }
        if let string = item.string(forType: .string), !string.isEmpty { return .text(string) }
        for (type, ext) in Self.keptImageTypes {
            if let data = item.data(forType: type), !data.isEmpty { return .image(data, ext) }
        }
        for type in item.types where UTType(type.rawValue)?.conforms(to: .image) == true {
            if let data = item.data(forType: type), let png = Self.png(from: data) { return .image(png, "png") }
        }
        return nil
    }

    static func png(from data: Data) -> Data? {
        if let rep = NSBitmapImageRep(data: data) { return rep.representation(using: .png, properties: [:]) }
        guard let image = NSImage(data: data), let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
