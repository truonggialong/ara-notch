import Foundation

/// Turns the HTML Notes returns through AppleScript (`body of note`), plus the note's `plaintext`,
/// into a `NoteDocument`. A small hand-written tag scanner: the HTML is not well-formed XML.
///
/// What AppleScript cannot tell apart is read as the plainest kind: a checklist or numbered list
/// comes out as a bullet list, a quote as a paragraph.
public enum NotesHTMLReader {
    public static func read(html: String, plainText: String) -> NoteDocument {
        var parser = Parser()
        for token in tokenize(html) { parser.consume(token) }
        return NoteDocument(blocks: parser.resolve(plainText: plainText))
    }

    // MARK: Tokens

    private enum Token {
        case text(String)
        case open(name: String, attributes: [String: String])
        case close(name: String)
        case object(raw: String)
    }

    private static let voidTags: Set<String> = ["br", "img", "hr", "meta", "link", "input"]

    private static func tokenize(_ html: String) -> [Token] {
        var tokens: [Token] = []
        var index = html.startIndex
        var text = ""
        func flushText() {
            if !text.isEmpty { tokens.append(.text(decodeEntities(text))); text = "" }
        }
        while index < html.endIndex {
            let character = html[index]
            guard character == "<", let next = html.index(index, offsetBy: 1, limitedBy: html.endIndex), next < html.endIndex,
                  html[next].isLetter || html[next] == "/",
                  let end = tagEnd(in: html, from: next) else {
                text.append(character)
                index = html.index(after: index)
                continue
            }
            flushText()
            let inner = String(html[next..<end])
            index = html.index(after: end)
            if inner.hasPrefix("/") {
                tokens.append(.close(name: inner.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()))
                continue
            }
            let (name, attributes) = parseTag(inner)
            if name == "object" {
                // Everything up to </object> is one token: tables keep their HTML verbatim.
                let start = html.index(before: next)
                if let close = html.range(of: "</object>", range: index..<html.endIndex) {
                    tokens.append(.object(raw: String(html[start..<close.upperBound])))
                    index = close.upperBound
                } else {
                    tokens.append(.object(raw: String(html[start...])))
                    index = html.endIndex
                }
                continue
            }
            tokens.append(.open(name: name, attributes: attributes))
            if voidTags.contains(name) || inner.hasSuffix("/") { tokens.append(.close(name: name)) }
        }
        flushText()
        return tokens
    }

    /// The index of the `>` that closes the tag starting at `from`, skipping quoted attribute values.
    private static func tagEnd(in html: String, from: String.Index) -> String.Index? {
        var quote: Character?
        var index = from
        while index < html.endIndex {
            let character = html[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ">" {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func parseTag(_ inner: String) -> (String, [String: String]) {
        let scalars = Array(inner)
        var position = 0
        var name = ""
        while position < scalars.count, !scalars[position].isWhitespace, scalars[position] != "/" {
            name.append(scalars[position]); position += 1
        }
        var attributes: [String: String] = [:]
        while position < scalars.count {
            while position < scalars.count, scalars[position].isWhitespace || scalars[position] == "/" { position += 1 }
            var key = ""
            while position < scalars.count, !scalars[position].isWhitespace, scalars[position] != "=", scalars[position] != "/" {
                key.append(scalars[position]); position += 1
            }
            guard !key.isEmpty else { break }
            var value = ""
            if position < scalars.count, scalars[position] == "=" {
                position += 1
                if position < scalars.count, scalars[position] == "\"" || scalars[position] == "'" {
                    let quote = scalars[position]; position += 1
                    while position < scalars.count, scalars[position] != quote { value.append(scalars[position]); position += 1 }
                    position += 1
                } else {
                    while position < scalars.count, !scalars[position].isWhitespace { value.append(scalars[position]); position += 1 }
                }
            }
            attributes[key.lowercased()] = decodeEntities(value)
        }
        return (name.lowercased(), attributes)
    }

    // MARK: Entities

    private static let namedEntities = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}"]

    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            if string[index] == "&", let semicolon = string[index...].firstIndex(of: ";"),
               string.distance(from: index, to: semicolon) <= 10 {
                let body = String(string[string.index(after: index)..<semicolon])
                var decoded: String?
                if body.hasPrefix("#") {
                    let digits = body.dropFirst()
                    let code = digits.hasPrefix("x") || digits.hasPrefix("X") ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    decoded = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    decoded = namedEntities[body]
                }
                if let decoded {
                    result += decoded
                    index = string.index(after: semicolon)
                    continue
                }
            }
            result.append(string[index])
            index = string.index(after: index)
        }
        return result
    }

    // MARK: Parser

    private struct Run {
        var text: String
        var style: TextStyle
        var link: URL?
        /// The innermost `font-size`, in pixels.
        var size: Int?
        /// Inside Notes' bold system font, its form for a heading.
        var boldFont = false
    }

    /// An open inline element: what it adds to the style while it is open.
    private struct Inline {
        var name: String
        var style: TextStyle = []
        var link: URL?
        var boldFont = false
        var size: Int?
        var textCountWhenOpened = 0
    }

    private enum Kind {
        case division
        case item(ListKind, indent: Int)
        case standaloneHeading
    }

    private struct Open {
        var kind: Kind
        var runs: [Run] = []
        var headingTag: Int?
        var table: String?
    }

    /// A block before the attachment lines of `plainText` have been looked at.
    private enum Pending {
        case block(NoteBlock)
        /// A block with no text; `plain` is a lone `<br>`, the others may stand for an attachment.
        case empty(plain: Bool)
        case table(html: String, cells: [[String]])
    }

    private struct Parser {
        var pending: [Pending] = []
        var lists: [ListKind] = []
        var stack: [Inline] = []
        var current: Open?
        var textCount = 0
        var brCount = 0

        mutating func consume(_ token: Token) {
            switch token {
            case .text(let text):
                guard current != nil else { return }
                textCount += 1
                append(text)
            case .object(let raw):
                if current == nil {
                    pending.append(.table(html: raw, cells: tableCells(raw)))
                } else {
                    current?.table = raw
                }
            case .open(let name, let attributes):
                open(name, attributes)
            case .close(let name):
                close(name)
            }
        }

        private mutating func append(_ text: String) {
            let style = stack.reduce(into: TextStyle()) { $0.formUnion($1.style) }
            let link = stack.last(where: { $0.link != nil })?.link
            let size = stack.last(where: { $0.size != nil })?.size
            current?.runs.append(Run(text: text, style: style, link: link, size: size, boldFont: stack.contains(where: \.boldFont)))
        }

        private mutating func open(_ name: String, _ attributes: [String: String]) {
            switch name {
            case "div":
                if current == nil { start(.division) }
            case "h1", "h2", "h3":
                let level = Int(name.dropFirst()) ?? 1
                if current == nil { start(.standaloneHeading) }
                current?.headingTag = level
            case "li":
                finishItem()
                start(.item(lists.last ?? .bullet, indent: max(lists.count - 1, 0)))
            case "ul":
                finishItem()
                lists.append(attributes["class"]?.contains("Apple-dash-list") == true ? .dash : .bullet)
            case "ol":
                finishItem()
                lists.append(.numbered)
            case "br":
                if current != nil { brCount += 1; append("\n") }
            case "b", "strong":
                stack.append(Inline(name: name, style: .bold, textCountWhenOpened: textCount))
            case "i", "em":
                stack.append(Inline(name: name, style: .italic, textCountWhenOpened: textCount))
            case "u":
                stack.append(Inline(name: name, style: .underline, textCountWhenOpened: textCount))
            case "strike", "s", "del":
                stack.append(Inline(name: name, style: .strikethrough, textCountWhenOpened: textCount))
            case "tt", "code":
                stack.append(Inline(name: name, style: .monospaced, textCountWhenOpened: textCount))
            case "font":
                let face = attributes["face"] ?? ""
                var inline = Inline(name: name, textCountWhenOpened: textCount)
                if face.localizedCaseInsensitiveContains("courier") || face.localizedCaseInsensitiveContains("monospace") {
                    inline.style = .monospaced
                }
                inline.boldFont = face == ".AppleSystemUIFontBold"
                stack.append(inline)
            case "span":
                var inline = Inline(name: name, textCountWhenOpened: textCount)
                inline.size = Self.fontSize(attributes["style"] ?? "")
                stack.append(inline)
            case "a":
                // Notes wraps a link in <u>; that wrapper is not an underline the author chose.
                if let top = stack.indices.last, stack[top].name == "u", stack[top].textCountWhenOpened == textCount {
                    stack[top].style = []
                }
                stack.append(Inline(name: name, link: attributes["href"].flatMap(URL.init(string:)), textCountWhenOpened: textCount))
            default:
                stack.append(Inline(name: name, textCountWhenOpened: textCount))
            }
        }

        private mutating func close(_ name: String) {
            switch name {
            case "div":
                if case .division? = current?.kind { finishBlock() }
            case "h1", "h2", "h3":
                if case .standaloneHeading? = current?.kind { finishBlock() }
            case "li":
                finishItem()
            case "ul", "ol":
                finishItem()
                _ = lists.popLast()
            case "br":
                break
            default:
                if let index = stack.lastIndex(where: { $0.name == name }) { stack.removeSubrange(index...) }
            }
        }

        private mutating func start(_ kind: Kind) {
            stack = []
            brCount = 0
            current = Open(kind: kind)
        }

        private mutating func finishItem() {
            if case .item? = current?.kind { finishBlock() }
        }

        private mutating func finishBlock() {
            guard var block = current else { return }
            current = nil
            stack = []
            if let table = block.table {
                pending.append(.table(html: table, cells: tableCells(table)))
                return
            }
            let allNewlines = block.runs.allSatisfy { $0.text.allSatisfy { $0 == "\n" } }
            if allNewlines {
                switch block.kind {
                case .division where block.headingTag == nil: pending.append(.empty(plain: brCount <= 1 && block.runs.count <= 1))
                case .item(let kind, let indent): pending.append(.block(.listItem(kind, indent: indent, [])))
                default: pending.append(.block(.heading(level: block.headingTag ?? 1, [])))
                }
                return
            }
            // A <br> that ends the block is not text.
            if let last = block.runs.indices.last, block.runs[last].text.hasSuffix("\n") { block.runs[last].text.removeLast() }

            let runs = Self.merged(block.runs)
            switch block.kind {
            case .item(let kind, let indent):
                pending.append(.block(.listItem(kind, indent: indent, runs)))
            case .division, .standaloneHeading:
                if let level = block.headingTag {
                    pending.append(.block(.heading(level: level, runs)))
                } else if let level = Self.boldSizeLevel(block.runs) {
                    pending.append(.block(.heading(level: level, runs)))
                } else if block.runs.allSatisfy({ $0.text.isEmpty || $0.style.contains(.monospaced) }) {
                    pending.append(.block(.code(runs.map(\.text).joined())))
                } else {
                    pending.append(.block(.paragraph(runs)))
                }
            }
        }

        /// Heading level when every run is bold at one size: Notes' bold system font at 21, 15 or 13 px
        /// (its form for h1–h3), or plain bold at 24, 21 or 18 px (what Notes keeps of AraNotch's headings).
        private static func boldSizeLevel(_ runs: [Run]) -> Int? {
            let texts = runs.filter { !$0.text.isEmpty }
            guard !texts.isEmpty, texts.allSatisfy({ $0.style.contains(.bold) }) else { return nil }
            let sizes = Set(texts.map(\.size))
            guard sizes.count == 1, let size = sizes.first ?? nil else { return nil }
            if texts.allSatisfy(\.boldFont) { return [21: 1, 15: 2, 13: 3][size] }
            if !texts.contains(where: \.boldFont) { return [24: 1, 21: 2, 18: 3][size] }
            return nil
        }

        private static func merged(_ runs: [Run]) -> [TextRun] {
            var result: [TextRun] = []
            for run in runs where !run.text.isEmpty {
                if let last = result.last, last.style == run.style, last.link == run.link {
                    result[result.count - 1].text += run.text
                } else {
                    result.append(TextRun(run.text, style: run.style, link: run.link))
                }
            }
            return result
        }

        private static func fontSize(_ style: String) -> Int? {
            guard let range = style.range(of: "font-size:") else { return nil }
            let digits = style[range.upperBound...].drop(while: { $0 == " " }).prefix(while: { $0.isNumber })
            return Int(digits)
        }

        // MARK: Tables

        private func tableCells(_ html: String) -> [[String]] {
            html.components(separatedBy: "<tr").dropFirst().map { row in
                row.components(separatedBy: "<td").dropFirst().map { cell in
                    guard let start = cell.firstIndex(of: ">") else { return "" }
                    let body = cell[cell.index(after: start)...].components(separatedBy: "</td>")[0]
                    return NotesHTMLReader.plainText(ofFragment: body)
                }
            }
        }

        // MARK: Attachments

        /// Gives every block its place: an empty block on an attachment line of `plainText` is an
        /// image; tables and images share one attachment counter, as AppleScript's `attachments`.
        mutating func resolve(plainText: String) -> [NoteBlock] {
            var lines = plainText.components(separatedBy: .newlines)
            if lines.count == pending.count + 1, lines.last?.isEmpty == true { lines.removeLast() }
            let aligned = lines.count == pending.count
            let attachmentLines = lines.filter { $0.contains("\u{FFFC}") }.count
            let tables = pending.filter { if case .table = $0 { true } else { false } }.count
            var imagesLeft = max(attachmentLines - tables, 0)

            var blocks: [NoteBlock] = []
            var attachment = 0
            for (index, item) in pending.enumerated() {
                switch item {
                case .block(let block):
                    blocks.append(block)
                case .table(let html, let cells):
                    blocks.append(.table(html: html, cells: cells))
                    attachment += 1
                case .empty(let plain):
                    // Without matching lines, fall back to the empty blocks that are not a lone <br>.
                    let isImage = aligned ? lines[index].contains("\u{FFFC}") : (!plain && imagesLeft > 0)
                    if isImage {
                        blocks.append(.image(attachmentIndex: attachment))
                        attachment += 1
                        imagesLeft -= 1
                    } else {
                        blocks.append(.paragraph([]))
                    }
                }
            }
            return blocks
        }
    }

    /// The text of a piece of HTML: tags dropped, entities decoded, blocks on their own lines.
    fileprivate static func plainText(ofFragment html: String) -> String {
        var text = ""
        for token in tokenize(html) {
            switch token {
            case .text(let string): text += string
            case .close(let name) where name == "div" || name == "p": text += "\n"
            default: break
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
