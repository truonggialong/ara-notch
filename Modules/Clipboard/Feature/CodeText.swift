import AppKit
import ClipboardCore
import SwiftUI

/// Turns source text into coloured, monospaced text. Colours follow the One Dark palette.
@MainActor
enum CodeHighlighter {
    /// Longer text is highlighted only up to this many characters.
    static let maxLength = 20_000

    private static let cache = NSCache<NSString, Box>()

    private final class Box {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    /// Forgets every highlighted text; called when the vault locks, as the cache holds clip text.
    static func clearCache() {
        cache.removeAllObjects()
    }

    static func attributed(_ text: String, fontSize: CGFloat) -> AttributedString {
        let source = String(text.prefix(maxLength))
        let key = "\(fontSize)|\(source)" as NSString
        if let cached = cache.object(forKey: key) { return cached.value }

        var result = AttributedString()
        for token in CodeTokenizer.tokenize(source) {
            var part = AttributedString(token.text)
            part.foregroundColor = color(for: token.kind)
            result.append(part)
        }
        result.font = .system(size: fontSize, design: .monospaced)
        cache.setObject(Box(result), forKey: key)
        return result
    }

    private static func color(for kind: CodeToken.Kind) -> Color {
        // The theme's own few colours, for the night sheet and for the day one.
        switch kind {
        case .keyword: return adaptive(dark: 0xF2A07E, light: 0xB93C0A)
        case .string: return adaptive(dark: 0x8FB9D6, light: 0x2F6388)
        case .comment: return adaptive(dark: 0x9A948A, light: 0x7C776E)
        case .number: return adaptive(dark: 0xE8C46A, light: 0x7A5C08)
        case .plain: return adaptive(dark: 0xF4F1EA, light: 0x1A1A1A)
        }
    }

    private static func adaptive(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ value: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1)
    }
}

/// Remembers which clips are code, so detection runs once per clip rather than on every redraw.
@MainActor
enum CodeRecognition {
    private static let cache = NSCache<NSNumber, NSNumber>()

    static func isCode(_ item: ClipItem) -> Bool {
        guard item.kind == .text else { return false }
        let key = NSNumber(value: item.id)
        if let cached = cache.object(forKey: key) { return cached.boolValue }
        let result = CodeDetector.looksLikeCode(item.text)
        cache.setObject(NSNumber(value: result), forKey: key)
        return result
    }
}
