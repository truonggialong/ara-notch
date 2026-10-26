import Foundation
import Testing
@testable import ClipboardCore

@Suite struct ClipSizeLimitTests {
    @Test func textOverTheLimitIsTooLargeToKeep() {
        let big = String(repeating: "đ", count: ClipboardStore.maxTextBytes / 2 + 1)
        #expect(ClipboardStore.isTooLarge(.text(big)))
        #expect(!ClipboardStore.isTooLarge(.text("xin chào")))
    }

    @Test func aPictureOverTheLimitIsTooLargeToKeep() {
        #expect(ClipboardStore.isTooLarge(.image(Data(count: ClipboardStore.maxImageBytes + 1))))
        #expect(!ClipboardStore.isTooLarge(.image(Data(count: 10))))
        #expect(!ClipboardStore.isTooLarge(.files(["/tmp/a.txt"])))
    }
}
