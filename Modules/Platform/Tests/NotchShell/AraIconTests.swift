import AppKit
import Foundation
import Testing
@testable import NotchShell

@Suite struct AraIconTests {
    /// The keys of one language's strings file.
    private func keys(language: String) throws -> Set<String> {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: root.appendingPathComponent("App/Resources/\(language).lproj/Localizable.strings"), encoding: .utf8)
        var keys: Set<String> = []
        for line in text.split(separator: "\n") where line.hasPrefix("\"") {
            if let end = line.dropFirst().firstIndex(of: "\"") {
                keys.insert(String(line[line.index(after: line.startIndex)..<end]))
            }
        }
        return keys
    }

    @Test func everyIconIsASymbolThisMacOSHas() {
        for icon in AraIcon.allCases {
            #expect(
                NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil) != nil,
                "\(icon.rawValue) uses the unknown symbol \(icon.symbolName)")
        }
    }

    @Test func everyIconHasANameInBothLanguages() throws {
        for language in ["en", "vi"] {
            let keys = try keys(language: language)
            for icon in AraIcon.allCases {
                #expect(keys.contains(icon.labelKey), "\(language) has no name for the icon \(icon.rawValue)")
            }
        }
    }
}
