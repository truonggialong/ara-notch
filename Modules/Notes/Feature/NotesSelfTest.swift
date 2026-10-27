import AppKit
import NotesCore

/// For checks without a person at the keyboard (`--self-test-notes <report>`): drives the notch's Notes page the way a person
/// would, with key and mouse events sent through the application (so menus, key equivalents and the text system handle
/// them as real ones), and writes each step to `report`. The general pasteboard is put back as it was. Ends by typing
/// a letter and quitting at once, so the last line of the note tells whether quitting saves.
extension NotesController {
    public func runSelfTest(report: URL) async {
        var lines: [String] = []
        func log(_ line: String) {
            lines.append(line)
            try? lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        }
        func pause(_ milliseconds: Int = 150) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }

        // A long note first, to time typing in it.
        guard let (window, text, editor) = await openNewNote(log: log) else { return }
        text.insertText((1...1500).map { "Dòng thử số \($0) cho độ dài" }.joined(separator: "\n"), replacementRange: text.selectedRange())
        await pause(2500)
        var times: [Double] = []
        for character in "độ trễ" {
            let start = Date()
            key(String(character), in: window)
            times.append(Date().timeIntervalSince(start) * 1000)
            await pause(30)
        }
        let catchUpStart = Date()
        await pause(700)  // the idle editor catches up after typing stops
        log(String(format: "lag: 1500 lines, keystroke max %.1f ms, mean %.1f ms (catch-up wait %.0f ms)",
                   times.max() ?? 0, times.reduce(0, +) / Double(max(times.count, 1)), Date().timeIntervalSince(catchUpStart) * 1000))
        _ = editor
        await flush()

        // The formatting note.
        guard let (window2, text2, editor2) = await openNewNote(log: log) else { return }
        type("Tự kiểm AraNotch\nđậm nghiêng gạch ngang mã liên\nmenu nổi\nĐề mục\nmục danh sách\n", in: window2)
        await pause(300)
        log("typed: \(text2.string.split(separator: "\n").count) lines, first '\(text2.string.prefix(16))'")

        for (word, keyChars, flags, name) in [("đậm", "b", NSEvent.ModifierFlags.command, "⌘B"), ("nghiêng", "i", .command, "⌘I"),
                                               ("gạch", "u", .command, "⌘U"), ("ngang", "X", [.command, .shift], "⌘⇧X"),
                                               ("mã", "M", [.command, .shift], "⌘⇧M")] {
            select(word, in: text2)
            await pause()
            key(keyChars, flags: flags, in: window2)
            await pause()
            log("\(name) on '\(word)': \(describe(word, in: text2))")
        }

        // The floating menu over a selection, and a click on its italic button.
        select("menu", in: text2)
        await pause(300)
        if let panel = NSApp.windows.first(where: { $0 is FormatPanel && $0.isVisible }) {
            let selection = text2.firstRect(forCharacterRange: text2.selectedRange(), actualRange: nil)
            log(String(format: "menu shown: panel %@ over selection %@ (gap %.0f pt)", NSStringFromRect(panel.frame),
                       NSStringFromRect(selection), panel.frame.minY - selection.maxY))
            click(NSPoint(x: 50, y: panel.frame.height / 2), in: panel)
            await pause()
            log("menu italic click (first click): \(describe("menu", in: text2))")
        } else {
            log("FAIL menu not shown over a selection")
        }

        // ⌘K with an address typed into the menu's field.
        select("liên", in: text2)
        await pause()
        key("k", flags: .command, in: window2)
        await pause(400)
        if let panel = NSApp.windows.first(where: { $0 is FormatPanel && $0.isVisible }), panel.isKeyWindow {
            type("apple.com", in: panel)
            key("\r", keyCode: 36, in: panel)
            await pause(300)
            log("⌘K link: \(describe("liên", in: text2))")
        } else {
            log("FAIL ⌘K: link field not focused (key window \(String(describing: NSApp.keyWindow)))")
        }

        // Paragraph kinds, as the toolbar does.
        select("Đề mục", in: text2)
        editor2.apply(.heading)
        await pause()
        select("mục danh sách", in: text2)
        editor2.apply(.bulletList)
        await pause()
        log("toolbar heading and list: '\(text2.string.components(separatedBy: "\n").suffix(4).joined(separator: " | "))'")

        // A picture pasted with ⌘V at the end, the pasteboard put back after.
        let saved = Self.savePasteboard()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(Self.samplePNG(), forType: .png)
        text2.setSelectedRange(NSRange(location: (text2.string as NSString).length, length: 0))
        window2.makeFirstResponder(text2)
        key("v", flags: .command, in: window2)
        await pause(400)
        Self.restorePasteboard(saved)
        let pictures = text2.string.filter { $0 == "\u{FFFC}" }.count
        log(pictures == 1 ? "⌘V picture: pasted" : "FAIL ⌘V picture: \(pictures) pictures in the text "
            + "(safety \(store.open.map { "\($0.safety)" } ?? "-"), staging \(store.staging.isAvailable), png bytes \(Self.samplePNG().count))")
        type("\nsau ảnh", in: window2)
        await pause(300)
        await flush()
        log("saved: \(store.saveState), note \(store.open?.id ?? "-")")

        // The last letter, then quit at once. ⌘Q is posted, not sent: sent from inside this task, the wait macOS runs
        // for the save to finish would block the very task that saves.
        type("Z", in: window2)
        log("typed Z, quitting")
        if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window2.windowNumber,
                                         context: nil, characters: "q", charactersIgnoringModifiers: "q", isARepeat: false, keyCode: 12) {
            NSApp.postEvent(event, atStart: false)
        }
        await pause(6000)
        log("⌘Q did not quit (no menu item takes it); quitting through the app")
        NSApp.terminate(nil)
    }

    private func openNewNote(log: (String) -> Void) async -> (NSWindow, NoteTextView, NoteEditorCoordinator)? {
        let before = store.open?.id
        newNote()
        var seen = ""
        let started = Date()
        for _ in 0..<450 {
            try? await Task.sleep(for: .milliseconds(100))
            let text = model.editor.editor?.textView
            let state = "open \(store.open?.id.split(separator: "/").last ?? "-") \(store.open.map { "\($0.safety)" } ?? "") "
                + "reloading \(store.isReloading) save \(store.saveState), editor \(text == nil ? "none" : "attached") "
                + "editable \(text?.isEditable ?? false) shown \(text?.window?.isVisible ?? false)"
            if state != seen {
                log(String(format: "  waiting %.1f s: ", Date().timeIntervalSince(started)) + state)
                seen = state
            }
            guard let open = store.open, open.id != before, open.safety == .editable,
                  let editor = model.editor.editor, case let text = editor.textView, text.isEditable,
                  let window = text.window, window.isVisible else { continue }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            window.makeFirstResponder(text)
            try? await Task.sleep(for: .milliseconds(300))
            log(String(format: "note open after %.1f s: %@, notch %@, key window %@", Date().timeIntervalSince(started), open.id, NSStringFromRect(window.frame),
                       window.isKeyWindow ? "yes" : "no"))
            return (window, text, editor)
        }
        log("FAIL no editable new note in 45 s (open: \(store.open?.id ?? "-"), state \(store.saveState))")
        return nil
    }

    private static func textView(in view: NSView?) -> NoteTextView? {
        guard let view else { return nil }
        if let text = view as? NoteTextView { return text }
        for subview in view.subviews { if let found = textView(in: subview) { return found } }
        return nil
    }

    private func key(_ characters: String, flags: NSEvent.ModifierFlags = [], keyCode: UInt16 = 0, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                                               timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                               context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                               isARepeat: false, keyCode: keyCode) else { continue }
            NSApp.sendEvent(event)
        }
    }

    private func type(_ text: String, in window: NSWindow) {
        for character in text {
            if character == "\n" { key("\r", keyCode: 36, in: window) } else { key(String(character), in: window) }
        }
    }

    private func click(_ point: NSPoint, in window: NSWindow) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            NSApp.sendEvent(event)
        }
    }

    private func select(_ word: String, in text: NSTextView) {
        let range = (text.string as NSString).range(of: word)
        text.window?.makeFirstResponder(text)
        text.setSelectedRange(range)
    }

    /// The word's font traits, underline, strike and link, as the text shows them.
    private func describe(_ word: String, in text: NSTextView) -> String {
        let range = (text.string as NSString).range(of: word)
        guard range.location != NSNotFound, let storage = text.textStorage else { return "word not found" }
        let attributes = storage.attributes(at: range.location, effectiveRange: nil)
        var parts: [String] = []
        if let font = attributes[.font] as? NSFont {
            let traits = font.fontDescriptor.symbolicTraits
            if traits.contains(.bold) { parts.append("bold") }
            if traits.contains(.italic) { parts.append("italic") }
            if traits.contains(.monoSpace) { parts.append("mono") }
        }
        if (attributes[.underlineStyle] as? Int ?? 0) != 0 { parts.append("underline") }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { parts.append("strike") }
        if let link = attributes[.link] { parts.append("link \(link)") }
        return parts.isEmpty ? "plain" : parts.joined(separator: ", ")
    }

    private static func savePasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in item.data(forType: type).map { (type, $0) } })
        }
    }

    private static func restorePasteboard(_ saved: [[NSPasteboard.PasteboardType: Data]]) {
        NSPasteboard.general.clearContents()
        let items = saved.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { NSPasteboard.general.writeObjects(items) }
    }

    private static func samplePNG() -> Data {
        let image = NSImage(size: NSSize(width: 120, height: 60), flipped: false) { rect in
            NSColor.systemGreen.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return Data() }
        return png
    }
}
