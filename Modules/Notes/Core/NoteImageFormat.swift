import Foundation

/// The kind of picture a file holds, told by its first bytes. Notes keeps a picture it got through HTML
/// as "public.data" in a file with no extension, so neither the type nor the name says it is a picture.
public enum NoteImageFormat {
    /// "png", "jpeg", "gif", "heic" or "tiff"; nil when the bytes are none of these.
    public static func fileExtension(of data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        func starts(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            bytes.count >= offset + prefix.count && Array(bytes[offset..<offset + prefix.count]) == prefix
        }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "jpeg" }
        if starts(Array("GIF8".utf8)) { return "gif" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "tiff" }
        if starts(Array("ftyp".utf8), at: 4),
           ["heic", "heix", "mif1", "msf1", "hevc"].contains(where: { starts(Array($0.utf8), at: 8) }) { return "heic" }
        return nil
    }
}

extension DecodedNote {
    /// The note with each `.file` block of an attachment in `indices` shown as an `.image` instead.
    public func showingAsImages(_ indices: Set<Int>) -> DecodedNote {
        guard !indices.isEmpty else { return self }
        var note = self
        note.document.blocks = document.blocks.map { block in
            if case .file(let index, _, _) = block, indices.contains(index) { return .image(attachmentIndex: index) }
            return block
        }
        return note
    }
}
