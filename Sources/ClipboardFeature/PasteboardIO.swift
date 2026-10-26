import AppKit
import ClipboardCore
import UniformTypeIdentifiers

enum PasteboardReader {
    static func types(of pasteboard: NSPasteboard) -> [String] {
        pasteboard.types?.map(\.rawValue) ?? []
    }

    /// Files win over text, and text over images: a spreadsheet cell or a web selection carries
    /// both a string and a rendered picture, and the string is what the user means.
    static func read(_ pasteboard: NSPasteboard) -> ClipContent? {
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL], !urls.isEmpty {
            return .files(urls.map(\.path))
        }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return .text(string)
        }
        // A colour copied from a colour panel or a design app carries no text: its hex code
        // is kept, and becomes a colour clip like a copied "#RRGGBB".
        if let color = NSColor(from: pasteboard) {
            return .text(hexCode(of: color))
        }
        // The picture as it came: turning it into what is stored is slow for a large one, so
        // it is done away from the main thread (`ClipImageData.stored(from:)`).
        if let png = pasteboard.data(forType: .png) {
            return .image(png)
        }
        if let tiff = pasteboard.data(forType: .tiff) {
            return .image(tiff)
        }
        return nil
    }
}

extension PasteboardReader {
    /// `#RRGGBB`, or `#RRGGBBAA` for a translucent colour, in sRGB.
    static func hexCode(of color: NSColor) -> String {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        var channels = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent]
        if srgb.alphaComponent < 1 {
            channels.append(srgb.alphaComponent)
        }
        return "#" + channels.map { String(format: "%02X", Int((min(max($0, 0), 1) * 255).rounded())) }.joined()
    }

    /// The formatted versions that accompany a copied string, if any.
    static func readRich(_ pasteboard: NSPasteboard) -> ClipRichData? {
        let rich = ClipRichData(rtf: pasteboard.data(forType: .rtf), html: pasteboard.data(forType: .html))
        return rich.isEmpty ? nil : rich
    }
}

enum PasteboardWriter {
    /// Puts the item back on the pasteboard. Returns false when its data is no longer available.
    /// - Parameter rich: formatted versions of a text item, written next to the plain string.
    static func write(
        _ item: ClipItem, imageData: Data?, rich: ClipRichData? = nil, to pasteboard: NSPasteboard
    ) -> Bool {
        switch item.kind {
        case .image:
            guard let imageData else { return false }
            pasteboard.clearContents()
            let type = ClipImageData.typeIdentifier(of: imageData) ?? UTType.png.identifier
            pasteboard.setData(imageData, forType: NSPasteboard.PasteboardType(type))
            let image = NSImage(data: imageData)
            // A photo kept as HEIC is also offered as PNG, which browsers and many apps expect.
            if type != UTType.png.identifier, let tiff = image?.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                pasteboard.setData(png, forType: .png)
            }
            // Many apps only accept TIFF.
            if let tiff = image?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
            return true
        case .file:
            pasteboard.clearContents()
            return pasteboard.writeObjects(item.filePaths.map { URL(fileURLWithPath: $0) as NSURL })
        case .text, .link, .color:
            pasteboard.clearContents()
            guard pasteboard.setString(item.text, forType: .string) else { return false }
            if let rtf = rich?.rtf {
                pasteboard.setData(rtf, forType: .rtf)
            }
            if let html = rich?.html {
                pasteboard.setData(html, forType: .html)
            }
            return true
        }
    }
}
