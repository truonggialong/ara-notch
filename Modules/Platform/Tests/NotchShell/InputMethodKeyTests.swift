import AppKit
import Testing
@testable import NotchShell

/// A window with a text field being typed in, as the notch or the clipboard panel has.
@MainActor
private func windowWithEditor() throws -> (NSWindow, NSTextView) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    window.contentView?.addSubview(field)
    #expect(window.makeFirstResponder(field))
    let editor = try #require(window.fieldEditor(true, for: field) as? NSTextView)
    #expect(window.firstResponder === editor)
    return (window, editor)
}

@MainActor
private func key(_ code: UInt16, _ characters: String, in window: NSWindow) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
}

@Suite @MainActor struct InputMethodKeyTests {
    @Test func whileAWordIsBeingComposedTheKeysBelongToTheInputMethod() throws {
        // Telex and VNI underline the syllable being built ("bà" on the way to "bài") until it
        // is committed; Return, Escape, Tab, the arrows and Delete are its to handle.
        let (window, editor) = try windowWithEditor()
        editor.setMarkedText("bà", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(editor.hasMarkedText())
        for (code, characters) in [(36, "\r"), (53, "\u{1b}"), (48, "\t"), (126, ""), (51, "\u{7f}")] {
            #expect(try key(UInt16(code), characters, in: window).isForInputMethod)
        }
    }

    @Test func onceTheWordIsCommittedTheKeysAreTheAppsAgain() throws {
        let (window, editor) = try windowWithEditor()
        editor.setMarkedText("bà", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.unmarkText()
        #expect(!(try key(36, "\r", in: window).isForInputMethod))
    }

    @Test func aKeyForAnotherWindowOrOneWithNothingTypedIsTheApps() throws {
        let (window, _) = try windowWithEditor()
        #expect(!(try key(36, "\r", in: window).isForInputMethod))
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10), styleMask: [], backing: .buffered, defer: false)
        #expect(!(try key(36, "\r", in: other).isForInputMethod))
    }
}
