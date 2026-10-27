import Foundation

/// An image's bytes and type, as embedded in a note.
public struct NoteImageData: Sendable {
    public var data: Data
    public var mimeType: String  // "image/png", "image/jpeg"…

    public init(data: Data, mimeType: String) {
        self.data = data
        self.mimeType = mimeType
    }
}

public enum NotesHTMLWriterError: Error, Equatable {
    case missingImage(Int)
    case unwritableBlock(String)
}

/// Turns a `NoteDocument` back into the HTML Notes accepts through AppleScript (`set body of note`),
/// using only the forms Notes was seen to keep. Every image is embedded as a data URI.
/// The inverse of `NotesHTMLReader`.
///
/// A `.code` block is one `<div>` of Courier text, its newlines written as `<br>`, so it reads back
/// as one block. A `.paragraph` whose runs are all monospaced would read back as `.code`.
///
/// Notes turns every font size it gets through HTML below 18 px into 11 px, smaller than text typed
/// in Notes, and lowers larger sizes by about three. So body text is written at 18 px (Notes keeps
/// 15 px, a little larger than its own) and headings as bold 28, 24 and 21 px (Notes keeps 24, 21, 18).
///
/// Notes collapses runs of spaces and drops tabs and leading spaces it gets through HTML, unless the text says
/// `white-space: pre-wrap`; so every sized span says it, and spaces and tabs are written as they are. Notes keeps
/// them and returns them raw, without the declaration (checked 2026-10-27).
public enum NotesHTMLWriter {
    static let bodySize = 18
    static func headingSize(_ level: Int) -> Int { [1: 28, 2: 24, 3: 21][level] ?? 28 }

    /// `images[i]` is the image with `attachmentIndex` i. A missing image throws; nothing is ever dropped.
    public static func write(_ document: NoteDocument, images: [Int: NoteImageData]) throws -> String {
        var html = ""
        var lists: [ListKind] = []  // open lists; the innermost `<li>` is left open
        for block in document.blocks {
            if case .listItem(let kind, let indent, let runs) = block {
                switch kind {
                case .bullet, .dash: break
                case .numbered: throw NotesHTMLWriterError.unwritableBlock("numberedList")
                case .checklist: throw NotesHTMLWriterError.unwritableBlock("checklist")
                }
                openItem(kind, depth: indent >= lists.count ? lists.count + 1 : max(1, indent + 1), lists: &lists, html: &html)
                html += sized(inline(runs) ?? "<br>", bodySize)
                continue
            }
            closeLists(&lists, to: 0, html: &html)
            switch block {
            case .paragraph(let runs):
                html += "<div>" + sized(inline(runs) ?? "<br>", bodySize) + "</div>"
            case .heading(let level, let runs):
                let body = inline(runs, dropping: .bold) ?? "<br>"
                html += "<div><b>" + sized(body, headingSize(level)) + "</b></div>"
            case .code(let text):
                html += "<div><font face=\"Courier\">" + sized(text.isEmpty ? "<br>" : escape(text), bodySize) + "</font></div>"
            case .image(let index):
                guard let image = images[index], !image.data.isEmpty else { throw NotesHTMLWriterError.missingImage(index) }
                let mime = image.mimeType.isEmpty ? "image/png" : image.mimeType
                html += "<div><img src=\"data:\(escape(mime));base64,\(image.data.base64EncodedString())\"></div>"
            case .table(let tableHTML, _):
                guard !tableHTML.isEmpty else { throw NotesHTMLWriterError.unwritableBlock("table") }
                html += tableHTML
            case .quote: throw NotesHTMLWriterError.unwritableBlock("quote")
            case .file: throw NotesHTMLWriterError.unwritableBlock("file")
            case .drawing: throw NotesHTMLWriterError.unwritableBlock("drawing")
            case .listItem: break
            }
        }
        closeLists(&lists, to: 0, html: &html)
        return html
    }

    // MARK: Lists

    private static func openTag(_ kind: ListKind) -> String {
        if case .dash = kind { return "<ul class=\"Apple-dash-list\">" }
        return "<ul>"
    }

    private static func closeLists(_ lists: inout [ListKind], to depth: Int, html: inout String) {
        while lists.count > depth {
            html += "</li></ul>"
            lists.removeLast()
        }
    }

    private static func openItem(_ kind: ListKind, depth: Int, lists: inout [ListKind], html: inout String) {
        if depth > lists.count {
            html += openTag(kind) + "<li>"
            lists.append(kind)
            return
        }
        closeLists(&lists, to: depth, html: &html)
        if lists[depth - 1] == kind {
            html += "</li><li>"
        } else {
            html += "</li></ul>" + openTag(kind) + "<li>"
            lists[depth - 1] = kind
        }
    }

    // MARK: Inline

    /// The runs as HTML, or nil when there is no text. Newlines inside a run become `<br>`.
    private static func inline(_ runs: [TextRun], dropping dropped: TextStyle = []) -> String? {
        let parts = runs.filter { !$0.text.isEmpty }.map { run -> String in
            var style = run.style
            style.subtract(dropped)
            var html = escape(run.text)
            if style.contains(.monospaced) { html = "<font face=\"Courier\">\(html)</font>" }
            if style.contains(.strikethrough) { html = "<strike>\(html)</strike>" }
            if style.contains(.underline) { html = "<u>\(html)</u>" }
            if style.contains(.italic) { html = "<i>\(html)</i>" }
            if style.contains(.bold) { html = "<b>\(html)</b>" }
            // A link is written plainly (not inside <u>); an underline goes inside it.
            if let link = run.link { html = "<a href=\"\(escape(link.absoluteString))\">\(html)</a>" }
            return html
        }
        return parts.isEmpty ? nil : parts.joined()
    }

    private static func sized(_ html: String, _ size: Int) -> String {
        "<span style=\"font-size: \(size)px; white-space: pre-wrap\">\(html)</span>"
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "\n": result += "<br>"
            default: result.append(character)
            }
        }
        return result
    }
}
