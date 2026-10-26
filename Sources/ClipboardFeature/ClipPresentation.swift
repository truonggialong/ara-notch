import AppKit
import ClipboardCore
import Foundation
import NotchShell
import SwiftUI

/// Display helpers shared by the notch cards and the panel rows.
extension ClipItem {
    /// A short single-paragraph excerpt; long clips are never laid out in full.
    var snippet: String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
    }

    var firstLine: String {
        snippet.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    var linkHost: String {
        URLComponents(string: snippet)?.host ?? snippet
    }

    var firstFileName: String {
        filePaths.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
    }

    var swatch: Color {
        // A clip stored as a colour may be bare hex digits, accepted when it was copied.
        guard let color = ClipColor.parse(text, allowingBareHex: kind == .color) else { return .clear }
        return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }

    /// The colour of the clip's kind: links sky blue, code mint, pictures peach, files
    /// mustard, colours lilac. Plain text has none.
    @MainActor var hue: AraHue? {
        kind == .text && CodeRecognition.isCode(self) ? .mint : kind.hue
    }

    var symbolName: String {
        kind.symbolName
    }

    /// Names the formatted versions stored with the clip, e.g. "RTF + HTML"; nil when plain.
    var richFormatLabel: String? {
        let formats = [rtfBlobName != nil ? "RTF" : nil, htmlBlobName != nil ? "HTML" : nil].compactMap { $0 }
        return formats.isEmpty ? nil : formats.joined(separator: " + ")
    }

    /// One-line label for a list row.
    var rowTitle: String {
        // A name the user gave the clip comes before anything derived from its content.
        if let title, !title.isEmpty { return title }
        switch kind {
        case .text, .color: return firstLine
        case .link: return linkTitle ?? snippet
        case .image: return L10n.string("clipboard.kind.image")
        case .file:
            let extra = filePaths.count - 1
            return extra > 0 ? "\(firstFileName) +\(extra)" : firstFileName
        }
    }

    /// "Just now" for the first minute; the formatter would say "in 0 seconds" there.
    @MainActor
    var relativeTime: String {
        let now = Date()
        guard now.timeIntervalSince(lastUsedAt) >= 60 else { return L10n.string("clipboard.time.now") }
        return ClipFormatters.relative.localizedString(for: lastUsedAt, relativeTo: now)
    }
}

@MainActor
enum ClipFormatters {
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static let byteCount: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }
}

extension ClipKind {
    /// The system symbol that stands for the kind.
    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .color: "paintpalette"
        case .image: "photo"
        case .file: "doc"
        }
    }

    /// The kind's name in the plural, as a filter is called.
    var filterTitle: String {
        L10n.string("library.kind.\(rawValue)")
    }

    /// The colour of the kind, where it has one.
    var hue: AraHue? {
        switch self {
        case .text: nil
        case .link: .sky
        case .image: .peach
        case .file: .mustard
        case .color: .lilac
        }
    }
}
