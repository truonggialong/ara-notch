import AppKit

enum NoteFormat: CaseIterable { case bold, italic, underline, strikethrough, monospaced, link, clear }
enum BlockFormat { case title, heading, subheading, body, bulletList, codeBlock }

/// The Telegram-style commands of the editor: a style is removed when the whole selection has it, otherwise added to all of it.
enum NoteFormatting {
    // MARK: Inline

    static func apply(_ f: NoteFormat, to text: NSTextStorage, range: NSRange, link: URL?) {
        let targets = characterRanges(in: text, range: range, for: f)
        guard !targets.isEmpty else { return }
        text.beginEditing()
        defer { text.endEditing() }
        switch f {
        case .bold, .italic, .monospaced:
            let on = !isActive(f, in: text, range: range)
            for target in targets { setFlag(f, on, text, target) }
        case .underline:
            toggle(.underlineStyle, NSUnderlineStyle.single.rawValue, f, text, range, targets)
        case .strikethrough:
            toggle(.strikethroughStyle, NSUnderlineStyle.single.rawValue, f, text, range, targets)
        case .link:
            for target in targets {
                if let link { text.addAttribute(.link, value: link, range: target) } else { text.removeAttribute(.link, range: target) }
            }
        case .clear:
            for target in targets {
                text.removeAttribute(.underlineStyle, range: target)
                text.removeAttribute(.strikethroughStyle, range: target)
                text.removeAttribute(.link, range: target)
                for flag in [NoteFormat.bold, .italic, .monospaced] { setFlag(flag, false, text, target) }
            }
        }
    }

    static func isActive(_ f: NoteFormat, in text: NSAttributedString, range: NSRange) -> Bool {
        var range = clamp(range, text.length)
        if range.length == 0 {   // a caret: the character before it
            guard text.length > 0 else { return false }
            range = NSRange(location: max(0, min(range.location, text.length) - (range.location > 0 ? 1 : 0)), length: 1)
        }
        let targets = characterRanges(in: text, range: range, for: f)
        guard !targets.isEmpty, f != .clear else { return false }
        for target in targets {
            for i in target.location..<(target.location + target.length) {
                let attributes = text.attributes(at: i, effectiveRange: nil)
                let has: Bool
                switch f {
                case .bold, .italic, .monospaced:
                    let flags = NoteAttributedText.flags(of: attributes[.font] as? NSFont, kind: NoteAttributedText.kind(of: attributes))
                    has = f == .bold ? flags.bold : f == .italic ? flags.italic : flags.mono
                case .underline: has = (attributes[.underlineStyle] as? Int ?? 0) != 0
                case .strikethrough: has = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
                case .link: has = attributes[.link] != nil
                case .clear: has = false
                }
                if !has { return false }
            }
        }
        return true
    }

    private static func toggle(_ key: NSAttributedString.Key, _ value: Int, _ f: NoteFormat, _ text: NSTextStorage,
                               _ range: NSRange, _ targets: [NSRange]) {
        let on = !isActive(f, in: text, range: range)
        for target in targets {
            if on { text.addAttribute(key, value: value, range: target) } else { text.removeAttribute(key, range: target) }
        }
    }

    /// Sets one of bold, italic, monospace on a run by rebuilding its fonts, keeping the other two and the block's size.
    private static func setFlag(_ f: NoteFormat, _ on: Bool, _ text: NSTextStorage, _ range: NSRange) {
        var changes: [(NSRange, NSFont)] = []
        text.enumerateAttributes(in: range, options: []) { attributes, sub, _ in
            let kind = NoteAttributedText.kind(of: attributes)
            var flags = NoteAttributedText.flags(of: attributes[.font] as? NSFont, kind: kind)
            switch f {
            case .bold: flags.bold = on
            case .italic: flags.italic = on
            default: flags.mono = on
            }
            changes.append((sub, NoteAttributedText.font(kind: kind, bold: flags.bold, italic: flags.italic, mono: flags.mono)))
        }
        for (sub, font) in changes { text.addAttribute(.font, value: font, range: sub) }
    }

    /// The characters a command works on: no newlines, no display-only marks, no attachments, and not what the block owns
    /// (the bold of a heading, the monospace of code).
    private static func characterRanges(in text: NSAttributedString, range: NSRange, for f: NoteFormat) -> [NSRange] {
        let range = clamp(range, text.length)
        let string = text.string as NSString
        var result: [NSRange] = []
        var current: NSRange?
        for i in range.location..<(range.location + range.length) {
            let attributes = text.attributes(at: i, effectiveRange: nil)
            let kind = NoteAttributedText.kind(of: attributes)
            var skip = string.character(at: i) == 0x0A || attributes[NoteAttribute.decoration] != nil
                || (string.character(at: i) == 0xFFFC && attributes[.attachment] != nil)
            if f == .bold && kind.isHeading { skip = true }
            if f == .monospaced && kind == .code { skip = true }
            if skip { if let c = current { result.append(c); current = nil }; continue }
            if let c = current { current = NSRange(location: c.location, length: c.length + 1) } else { current = NSRange(location: i, length: 1) }
        }
        if let c = current { result.append(c) }
        return result
    }

    private static func clamp(_ range: NSRange, _ length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    // MARK: Blocks

    static func apply(_ f: BlockFormat, to text: NSTextStorage, range: NSRange) {
        let target: NoteBlockKind
        switch f {
        case .title: target = .h1
        case .heading: target = .h2
        case .subheading: target = .h3
        case .body: target = .paragraph
        case .bulletList: target = .bullet
        case .codeBlock: target = .code
        }
        let string = text.string as NSString
        let range = clamp(range, string.length)
        guard string.length > 0 else { return }
        var paragraphs: [NSRange] = []
        let whole = string.paragraphRange(for: range)
        string.enumerateSubstrings(in: whole, options: .byParagraphs) { _, _, enclosing, _ in paragraphs.append(enclosing) }
        paragraphs = paragraphs.filter { !startsWithAttachment(text, $0) }
        guard !paragraphs.isEmpty else { return }

        var newKind = target
        if f == .bulletList || f == .codeBlock {
            let all = paragraphs.allSatisfy { NoteAttributedText.kind(of: text.attributes(at: $0.location, effectiveRange: nil)) == target }
            if all { newKind = .paragraph }
        }
        text.beginEditing()
        defer { text.endEditing() }
        for paragraph in paragraphs.reversed() { convert(paragraph, to: newKind, in: text) }
    }

    private static func startsWithAttachment(_ text: NSAttributedString, _ range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        return (text.string as NSString).character(at: range.location) == 0xFFFC
            && text.attribute(.attachment, at: range.location, effectiveRange: nil) != nil
    }

    private static func convert(_ range: NSRange, to kind: NoteBlockKind, in text: NSTextStorage) {
        var range = range
        let first = text.attributes(at: range.location, effectiveRange: nil)
        let oldKind = NoteAttributedText.kind(of: first)
        let indent = oldKind.isList ? (first[NoteAttribute.indent] as? Int ?? 0) : 0

        var mark = 0   // the display-only mark of the old list kind
        while mark < range.length, text.attribute(NoteAttribute.decoration, at: range.location + mark, effectiveRange: nil) != nil { mark += 1 }
        if mark > 0 {
            text.deleteCharacters(in: NSRange(location: range.location, length: mark))
            range.length -= mark
        }

        var fonts: [(NSRange, NSFont)] = []
        text.enumerateAttributes(in: range, options: []) { attributes, sub, _ in
            let flags = NoteAttributedText.flags(of: attributes[.font] as? NSFont, kind: oldKind)
            fonts.append((sub, NoteAttributedText.font(kind: kind, bold: flags.bold, italic: flags.italic, mono: flags.mono)))
        }
        for (sub, font) in fonts { text.addAttribute(.font, value: font, range: sub) }
        text.addAttribute(NoteAttribute.block, value: kind.rawValue, range: range)
        text.addAttribute(.paragraphStyle, value: NoteAttributedText.paragraphStyle(kind: kind, indent: indent), range: range)
        if kind.isList { text.addAttribute(NoteAttribute.indent, value: indent, range: range) }
        else { text.removeAttribute(NoteAttribute.indent, range: range) }

        if kind == .bullet {
            var attributes = NoteAttributedText.blockAttributes(kind: kind, indent: indent)
            attributes[NoteAttribute.decoration] = true
            text.insert(NSAttributedString(string: "• ", attributes: attributes), at: range.location)
        }
    }
}
