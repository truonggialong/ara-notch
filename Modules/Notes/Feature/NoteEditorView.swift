import AppKit
import Combine
import NotesCore
import SwiftUI

/// The editor of the open note, shared by the notch page and the Notes window.
struct NoteEditorView: NSViewRepresentable {
    let store: NotesStore
    let imageSize: NoteImageSize
    /// Told when the text gets or loses the keyboard (the notch stays open meanwhile).
    var onFocusChange: ((Bool) -> Void)?

    init(store: NotesStore, imageSize: NoteImageSize) {
        self.store = store
        self.imageSize = imageSize
    }

    func focusChanged(_ action: @escaping (Bool) -> Void) -> NoteEditorView {
        var copy = self
        copy.onFocusChange = action
        return copy
    }

    func makeCoordinator() -> NoteEditorCoordinator {
        NoteEditorCoordinator(store: store, imageSize: imageSize)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        coordinator.onFocusChange = onFocusChange
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let text = coordinator.textView
        text.minSize = .zero
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        coordinator.watchScrolling(of: scroll)
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.onFocusChange = onFocusChange
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: NoteEditorCoordinator) {
        coordinator.commitNow()
        coordinator.popover.tearDown()
    }
}

/// Keeps one text view and the store's open note in step. The text is built from one load of the note
/// (`OpenNote.generation`); every edit is sent with that generation, and a new load rebuilds the text.
@MainActor
final class NoteEditorCoordinator: NSObject, NSTextViewDelegate, NoteTextViewHost {
    /// Every live editor, so their unsent edits can be handed to the store before it saves.
    private static let live = NSHashTable<NoteEditorCoordinator>.weakObjects()

    /// Sends every editor's unsent edit to the store.
    static func commitAll() {
        for editor in live.allObjects { editor.commitNow() }
    }

    let store: NotesStore
    let imageSize: NoteImageSize
    let textView: NoteTextView
    lazy var popover = FormatPopover(editor: self)
    var onFocusChange: ((Bool) -> Void)?

    /// The load the text was built from; nil while no note is open.
    private(set) var generation: Int?
    /// The document the text was built from: what table attachments are looked up in.
    private var loadedDocument = NoteDocument(blocks: [])
    private var commitScheduled = false
    private var isRebuilding = false
    private var isStripping = false
    private var cancellables: Set<AnyCancellable> = []

    init(store: NotesStore, imageSize: NoteImageSize) {
        self.store = store
        self.imageSize = imageSize
        textView = NoteTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
        super.init()
        textView.host = self
        textView.delegate = self
        textView.isRichText = true
        textView.importsGraphics = false   // pictures come in through NoteTextView's paste and drop only
        textView.allowsImageEditing = false
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .cursor: NSCursor.pointingHand]
        Self.live.add(self)
        apply(store.open, store.saveState)
        // The values come before the store's properties change, so they are taken from the sink, not the store.
        store.$open.combineLatest(store.$saveState)
            .sink { [weak self] open, state in self?.apply(open, state) }
            .store(in: &cancellables)
    }

    // MARK: Following the store

    private func apply(_ open: OpenNote?, _ state: NoteSaveState) {
        if open?.generation != generation { rebuild(open) }
        let editable = open?.safety == .editable && state != .conflict && state != .deleted
        if textView.isEditable != editable {
            textView.isEditable = editable
            if !editable { popover.hide() }
        }
    }

    private func rebuild(_ open: OpenNote?) {
        commitScheduled = false   // an edit not sent yet belonged to the load being replaced
        popover.hide()
        generation = open?.generation
        loadedDocument = open?.document ?? NoteDocument(blocks: [])
        let images = (open?.images ?? [:]).compactMapValues { NSImage(contentsOf: $0) }
        isRebuilding = true
        defer { isRebuilding = false }
        textView.textStorage?.setAttributedString(
            open.map { NoteAttributedText.make($0.document, images: images, imageSize: imageSize) } ?? NSAttributedString())
        textView.undoManager?.removeAllActions()
        let start = Self.caretOutOfMark(NSRange(location: 0, length: 0), from: NSRange(location: 0, length: 0), in: textView)
        textView.setSelectedRange(start)
        textView.typingAttributes = NoteAttributedText.cleanTypingAttributes(
            textView.textStorage.flatMap { $0.length > 0 ? $0.attributes(at: min(start.location, $0.length - 1), effectiveRange: nil) : nil }
                ?? NoteAttributedText.typingAttributes(for: .paragraph))
    }

    // MARK: Sending edits

    func textDidChange(_ notification: Notification) {
        guard !isRebuilding, !isStripping else { return }
        stripBareAttachments()
        textView.typingAttributes = NoteAttributedText.cleanTypingAttributes(textView.typingAttributes)
        scheduleCommit()
    }

    private func scheduleCommit() {
        guard !commitScheduled else { return }
        commitScheduled = true
        let scheduledFor = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.commitScheduled, self.generation == scheduledFor else { return }
            self.commitNow()
        }
    }

    /// Sends the text to the store now, if it changed since the last send.
    func commitNow() {
        guard commitScheduled else { return }
        commitScheduled = false
        guard let generation, let storage = textView.textStorage else { return }
        store.edit(NoteAttributedText.document(from: storage, original: loadedDocument), generation: generation)
    }

    /// A U+FFFC that is not an indexed attachment (a bare attachment, or the character alone) could not be
    /// written back, or would be written as text: it is taken out, as an undoable edit.
    private func stripBareAttachments() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        let string = storage.string as NSString
        var bare: [NSRange] = []
        var search = NSRange(location: 0, length: string.length)
        while true {
            let found = string.range(of: "\u{FFFC}", options: .literal, range: search)
            guard found.location != NSNotFound else { break }
            let attributes = storage.attributes(at: found.location, effectiveRange: nil)
            if attributes[.attachment] == nil || attributes[NoteAttribute.attachmentIndex] == nil { bare.append(found) }
            let next = NSMaxRange(found)
            search = NSRange(location: next, length: string.length - next)
        }
        guard !bare.isEmpty else { return }
        let selection = textView.selectedRange()
        isStripping = true
        defer { isStripping = false }
        guard textView.shouldChangeText(inRanges: bare.map { NSValue(range: $0) },
                                        replacementStrings: Array(repeating: "", count: bare.count)) else { return }
        storage.beginEditing()
        for range in bare.reversed() { storage.deleteCharacters(in: range) }
        storage.endEditing()
        let removedBefore = bare.filter { $0.location < selection.location }.count
        textView.setSelectedRange(NSRange(location: max(0, min(selection.location - removedBefore, storage.length)), length: 0))
        textView.didChangeText()
    }

    // MARK: Selection

    func textViewDidChangeSelection(_ notification: Notification) {
        textView.typingAttributes = NoteAttributedText.cleanTypingAttributes(textView.typingAttributes)
        popover.selectionChanged()
    }

    func textView(_ textView: NSTextView, willChangeSelectionFromCharacterRange oldRange: NSRange,
                  toCharacterRange newRange: NSRange) -> NSRange {
        Self.caretOutOfMark(newRange, from: oldRange, in: textView)
    }

    /// The length of the display-only mark ("• ", "12. ") at the start of the paragraph that starts at `start`.
    static func markLength(at start: Int, in text: NSAttributedString) -> Int {
        var span = 0
        while start + span < text.length, text.attribute(NoteAttribute.decoration, at: start + span, effectiveRange: nil) != nil {
            span += 1
        }
        return span
    }

    /// A caret placed on a line's mark goes just after it; moving left off that spot goes to the line before.
    static func caretOutOfMark(_ range: NSRange, from old: NSRange, in textView: NSTextView) -> NSRange {
        guard let storage = textView.textStorage, storage.length > 0 else { return range }
        let string = storage.string as NSString
        let location = min(range.location, string.length)
        let start = string.lineRange(for: NSRange(location: location, length: 0)).location
        let mark = markLength(at: start, in: storage)
        guard mark > 0, location < start + mark else { return range }
        let afterMark = start + mark
        if range.length == 0 {
            if old.length == 0, old.location == afterMark, location < afterMark, start > 0 {
                return NSRange(location: start - 1, length: 0)
            }
            return NSRange(location: afterMark, length: 0)
        }
        let end = range.location + range.length
        return end <= afterMark ? NSRange(location: afterMark, length: 0) : NSRange(location: afterMark, length: end - afterMark)
    }

    // MARK: Lists

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard textView.isEditable, let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        guard selection.length == 0 else { return false }
        let string = storage.string as NSString
        let line = string.lineRange(for: NSRange(location: min(selection.location, string.length), length: 0))
        let mark = Self.markLength(at: line.location, in: storage)
        guard mark > 0 else { return false }
        let kind = NoteAttributedText.kind(of: storage.attributes(at: line.location, effectiveRange: nil))
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            guard kind == .bullet || kind == .dash else { return false }
            let content = line.length - mark - (string.substring(with: line).hasSuffix("\n") ? 1 : 0)
            if content == 0 {
                endList(line)
                return true
            }
            let indent = storage.attribute(NoteAttribute.indent, at: line.location, effectiveRange: nil) as? Int ?? 0
            let attributes = NoteAttributedText.blockAttributes(kind: kind, indent: indent)
            var decoration = attributes
            decoration[NoteAttribute.decoration] = true
            let insertion = NSMutableAttributedString(string: "\n", attributes: attributes)
            insertion.append(NSAttributedString(string: string.substring(with: NSRange(location: line.location, length: mark)),
                                                attributes: decoration))
            replace(selection, with: insertion)
            textView.typingAttributes = NoteAttributedText.cleanTypingAttributes(attributes)
            return true
        case #selector(NSResponder.deleteBackward(_:)):
            guard selection.location == line.location + mark else { return false }
            endList(line)
            return true
        default:
            return false
        }
    }

    /// The list item becomes a plain paragraph, its mark gone.
    private func endList(_ line: NSRange) {
        guard let storage = textView.textStorage, textView.shouldChangeText(in: line, replacementString: nil) else { return }
        NoteFormatting.apply(.body, to: storage, range: NSRange(location: line.location, length: 0))
        textView.setSelectedRange(NSRange(location: line.location, length: 0))
        textView.typingAttributes = NoteAttributedText.typingAttributes(for: .paragraph)
        textView.didChangeText()
    }

    private func replace(_ range: NSRange, with text: NSAttributedString) {
        guard let storage = textView.textStorage, textView.shouldChangeText(in: range, replacementString: text.string) else { return }
        storage.replaceCharacters(in: range, with: text)
        textView.setSelectedRange(NSRange(location: range.location + text.length, length: 0))
        textView.didChangeText()
    }

    /// An edit that would cut into a line's mark takes the whole mark.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        // nil: only attributes change (formatting), which never touches a mark. While bare attachments are taken
        // out, nothing is widened.
        guard !isStripping, let storage = textView.textStorage, let replacementString else { return true }
        let widened = Self.widenedOverMarks(range, in: storage)
        guard widened != range else { return true }
        // Typed text only (paste and drop widen before they ask): plain characters, without U+FFFC.
        let text = replacementString.replacingOccurrences(of: "\u{FFFC}", with: "")
        let scheduledFor = generation
        DispatchQueue.main.async { [weak self, weak textView] in
            guard let self, let textView, self.generation == scheduledFor, let storage = textView.textStorage,
                  NSMaxRange(widened) <= storage.length else { return }
            let attributes = NoteAttributedText.cleanTypingAttributes(textView.typingAttributes)
            self.replace(widened, with: NSAttributedString(string: text, attributes: attributes))
        }
        return false
    }

    func rangeForReplacing(_ range: NSRange) -> NSRange {
        guard let storage = textView.textStorage else { return range }
        return Self.widenedOverMarks(range, in: storage)
    }

    /// A change that would cut into a line's mark takes the whole mark: one that starts inside a mark starts at its
    /// line, and one that ends inside a mark, or at the start of a marked line, ends after the mark.
    static func widenedOverMarks(_ range: NSRange, in storage: NSAttributedString) -> NSRange {
        let string = storage.string as NSString
        var widened = range
        let startLine = string.lineRange(for: NSRange(location: min(range.location, string.length), length: 0)).location
        let startMark = Self.markLength(at: startLine, in: storage)
        if range.location > startLine, range.location < startLine + startMark {
            widened = NSRange(location: startLine, length: range.location + range.length - startLine)
        }
        let end = widened.location + widened.length
        if range.length > 0, end < string.length {
            // Also a deletion that ends at a marked line's start (its newline), so the mark is not left mid-line.
            let endLine = string.lineRange(for: NSRange(location: end, length: 0)).location
            let endMark = Self.markLength(at: endLine, in: storage)
            if end >= endLine, end < endLine + endMark { widened.length = endLine + endMark - widened.location }
        }
        return widened
    }

    // MARK: Formatting

    func perform(_ format: NoteFormat) -> Bool {
        guard textView.isEditable else { return false }
        if format == .link {
            popover.beginLink()
            return true
        }
        return apply(format, link: nil)
    }

    /// Applies a format to the selection, or to what is typed next when nothing is selected.
    @discardableResult
    func apply(_ format: NoteFormat, link: URL?) -> Bool {
        guard textView.isEditable, let storage = textView.textStorage else { return false }
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.typingAttributes = Self.toggled(format, in: textView.typingAttributes)
            return true
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return false }
        NoteFormatting.apply(format, to: storage, range: range, link: link)
        textView.didChangeText()
        textView.setSelectedRange(range)
        popover.refresh()
        return true
    }

    func isActive(_ format: NoteFormat) -> Bool {
        guard let storage = textView.textStorage else { return false }
        return NoteFormatting.isActive(format, in: storage, range: textView.selectedRange())
    }

    /// The link on the selection, if all of it is one.
    var selectedLink: URL? {
        guard let storage = textView.textStorage, storage.length > 0 else { return nil }
        let range = textView.selectedRange()
        let value = storage.attribute(.link, at: min(range.location, storage.length - 1), effectiveRange: nil)
        return (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
    }

    /// Typing attributes with one style turned on or off.
    static func toggled(_ format: NoteFormat, in attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = NoteAttributedText.cleanTypingAttributes(attributes)
        let kind = NoteAttributedText.kind(of: result)
        var flags = NoteAttributedText.flags(of: result[.font] as? NSFont, kind: kind)
        switch format {
        case .bold: flags.bold.toggle()
        case .italic: flags.italic.toggle()
        case .monospaced: flags.mono.toggle()
        case .underline:
            result[.underlineStyle] = (result[.underlineStyle] as? Int ?? 0) != 0 ? nil : NSUnderlineStyle.single.rawValue
        case .strikethrough:
            result[.strikethroughStyle] = (result[.strikethroughStyle] as? Int ?? 0) != 0 ? nil : NSUnderlineStyle.single.rawValue
        case .clear:
            flags = (false, false, false)
            result[.underlineStyle] = nil
            result[.strikethroughStyle] = nil
            result[.link] = nil
        case .link:
            break
        }
        result[.font] = NoteAttributedText.font(kind: kind, bold: flags.bold, italic: flags.italic, mono: flags.mono)
        return result
    }

    // MARK: Images

    func imageLine(for data: Data, fileExtension: String) -> NSAttributedString? {
        guard textView.isEditable, let index = store.addImage(data, fileExtension: fileExtension) else { return nil }
        let image = NSImage(data: data).map { [index: $0] } ?? [:]
        return NoteAttributedText.make(NoteDocument(blocks: [.image(attachmentIndex: index), .paragraph([])]),
                                       images: image, imageSize: imageSize)
    }

    // MARK: Focus and scrolling

    func focusChanged(_ isFocused: Bool) {
        if !isFocused {
            commitNow()
            if !popover.isEditingLink { popover.hide() }
        }
        onFocusChange?(isFocused || popover.isEditingLink)
    }

    func linkEditingChanged(_ isEditing: Bool) {
        onFocusChange?(isEditing || textView.window?.firstResponder === textView)
    }

    /// The menu goes away when the user scrolls (not when the text grows or the view is laid out again).
    func watchScrolling(of scroll: NSScrollView) {
        NotificationCenter.default.publisher(for: NSScrollView.willStartLiveScrollNotification, object: scroll)
            .sink { [weak self] _ in self?.popover.hide() }
            .store(in: &cancellables)
    }
}
