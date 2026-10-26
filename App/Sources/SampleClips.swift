import AppKit
import ClipboardCore
import ClipboardFeature

/// A fixed set of clips covering every kind, for `--seed-clipboard`.
@MainActor
enum SampleClips {
    static func add(to clipboard: ClipboardController) {
        let notes = ClipSource(bundleID: "com.apple.Notes", appName: "Notes")
        let safari = ClipSource(bundleID: "com.apple.Safari", appName: "Safari")
        let code = ClipSource(bundleID: "com.microsoft.VSCode", appName: "Code")
        let finder = ClipSource(bundleID: "com.apple.finder", appName: "Finder")

        // Added oldest first; the page shows the newest first.
        if let image = sampleImage() {
            clipboard.capture(.image(image), source: safari)
        }
        clipboard.capture(.files(["/Users/demo/Documents/Báo cáo quý 3.pdf", "/Users/demo/Documents/Ghi chú.txt"]), source: finder)
        clipboard.capture(.text("func greet(_ name: String) -> String {\n    \"Xin chào, \\(name)!\"\n}"), source: code)
        clipboard.capture(.text("#4A90D9"), source: code)
        clipboard.capture(.text("https://www.apple.com/vn/macbook-pro/"), source: safari)
        clipboard.capture(.text("Lịch họp tuần này: thứ Ba 9 giờ, phòng họp tầng 3."), source: notes)

        let formatted = NSAttributedString(
            string: "Hạn nộp: thứ Sáu", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = try? formatted.data(
            from: NSRange(location: 0, length: formatted.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        clipboard.capture(.text(formatted.string), rich: ClipRichData(rtf: rtf), source: notes)
    }

    /// Two boards over the sample clips, for `--seed-boards`. Expects `add(to:)` to have run.
    static func addBoards(to clipboard: ClipboardController) {
        clipboard.createBoard(name: "Công việc", symbolName: "briefcase")
        clipboard.createBoard(name: "Code", symbolName: "chevron.left.forwardslash.chevron.right")

        // Newest first: formatted note, meeting note, link, colour, code, files, image.
        let ids = clipboard.newestItemIDs
        guard ids.count >= 6 else { return }
        for index in [1, 2, 5] {
            clipboard.pin(itemID: ids[index], toBoardNamed: "Công việc")
        }
        clipboard.pin(itemID: ids[4], toBoardNamed: "Công việc")
        clipboard.pin(itemID: ids[4], toBoardNamed: "Code")
    }

    private static func sampleImage() -> Data? {
        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: .systemOrange, ending: .systemPurple)?.draw(in: rect, angle: 45)
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}
