import AppKit
import ClipboardCore
import Foundation
import Testing
@testable import ClipboardFeature

@MainActor
@Suite struct ClipEditorWindowTests {
    private func imageClip() -> ClipItem {
        ClipItem(
            id: 7, kind: .image, text: "", blobName: "a.png", source: ClipSource(bundleID: nil, appName: nil),
            createdAt: Date(), lastUsedAt: Date(), byteSize: 10)
    }

    @Test func aNewNoteStartsWithTheCursorInItsText() throws {
        let window = ClipEditorWindows.makeWindow(model: ClipEditorModel(item: nil), title: "New Note")
        ClipEditorWindows.focusFirstField(in: window, prefersText: true)
        let responder = try #require(window.firstResponder as? NSTextView)
        #expect(!responder.isFieldEditor)
    }

    @Test func aClipWithoutEditableTextStartsInItsTitle() throws {
        let window = ClipEditorWindows.makeWindow(model: ClipEditorModel(item: imageClip()), title: "Edit")
        ClipEditorWindows.focusFirstField(in: window, prefersText: false)
        let responder = try #require(window.firstResponder as? NSTextView)
        #expect(responder.isFieldEditor)
    }

    @Test func theWindowHasItsFullSizeBeforeItIsCentred() throws {
        let window = ClipEditorWindows.makeWindow(model: ClipEditorModel(item: nil), title: "New Note")
        #expect(window.frame.width >= 460)
        let screen = try #require(window.screen ?? NSScreen.main)
        #expect(abs(window.frame.midX - screen.visibleFrame.midX) <= 1)
    }

    @Test func theTextShowsAScrollBarOnlyWhileScrolling() throws {
        let window = ClipEditorWindows.makeWindow(model: ClipEditorModel(item: nil), title: "New Note")
        ClipEditorWindows.focusFirstField(in: window, prefersText: true)
        let scroll = try #require(window.contentView.flatMap { Self.scrollView(in: $0) })
        #expect(scroll.scrollerStyle == .overlay)
        #expect(scroll.autohidesScrollers)
    }

    private static func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for subview in view.subviews {
            if let found = scrollView(in: subview) { return found }
        }
        return nil
    }
}
