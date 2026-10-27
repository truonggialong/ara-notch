import AppKit
import NotesCore
import UniformTypeIdentifiers

/// A read-only preview drawn in place of a table, a file or a drawing inside the editor text.
final class NoteAttachmentCell: NSTextAttachmentCell {
    enum Content {
        case table([[String]])
        case file(name: String, uti: String)
        case drawing
    }

    private var content: Content = .drawing

    convenience init(content: Content) {
        self.init(textCell: "")
        self.content = content
    }

    override init(textCell string: String) { super.init(textCell: string) }
    override init(imageCell image: NSImage?) { super.init(imageCell: image) }
    required init(coder: NSCoder) { super.init(coder: coder) }

    private static let columnWidth: CGFloat = 72
    private static let rowHeight: CGFloat = 18
    private static let font = NSFont.systemFont(ofSize: 10)

    override func cellSize() -> NSSize {
        switch content {
        case .table(let cells):
            let columns = max(1, cells.map(\.count).max() ?? 1)
            return NSSize(width: CGFloat(columns) * Self.columnWidth, height: CGFloat(max(1, cells.count)) * Self.rowHeight)
        case .file: return NSSize(width: 220, height: 36)
        case .drawing: return NSSize(width: 72, height: 54)
        }
    }

    override func cellBaselineOffset() -> NSPoint { .zero }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.labelColor]
        NSColor.separatorColor.setStroke()
        switch content {
        case .table(let cells):
            for (r, row) in cells.enumerated() {
                for (c, text) in row.enumerated() {
                    let cell = NSRect(x: cellFrame.minX + CGFloat(c) * Self.columnWidth, y: cellFrame.minY + CGFloat(r) * Self.rowHeight,
                                      width: Self.columnWidth, height: Self.rowHeight)
                    NSBezierPath(rect: cell).stroke()
                    (text as NSString).draw(in: cell.insetBy(dx: 3, dy: 2), withAttributes: attributes)
                }
            }
        case .file(let name, let uti):
            let icon = NSWorkspace.shared.icon(for: UTType(uti) ?? .data)
            icon.draw(in: NSRect(x: cellFrame.minX, y: cellFrame.minY + 2, width: 32, height: 32))
            (name as NSString).draw(in: NSRect(x: cellFrame.minX + 38, y: cellFrame.minY + 10, width: cellFrame.width - 38, height: 16),
                                    withAttributes: attributes)
        case .drawing:
            NSBezierPath(roundedRect: cellFrame.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
            let symbol = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: nil)
            symbol?.draw(in: NSRect(x: cellFrame.midX - 14, y: cellFrame.midY - 14, width: 28, height: 28))
        }
    }
}
