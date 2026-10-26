import AppKit
import ClipboardCore
import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct PasteboardColorTests {
    private func board() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("aranotch-tests-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    @Test func aColourCopiedAsAColourIsKeptAsItsHexCode() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([NSColor(srgbRed: 1, green: 0.5333, blue: 0, alpha: 1)])
        #expect(PasteboardReader.read(pasteboard) == .text("#FF8800"))
    }

    @Test func aTranslucentColourKeepsItsAlpha() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 0.5)])
        #expect(PasteboardReader.read(pasteboard) == .text("#0000FF80"))
    }

    @Test func textNextToAColourWins() {
        let pasteboard = board()
        defer { pasteboard.releaseGlobally() }
        pasteboard.writeObjects([NSColor.red])
        pasteboard.setString("đỏ", forType: .string)
        #expect(PasteboardReader.read(pasteboard) == .text("đỏ"))
    }
}
