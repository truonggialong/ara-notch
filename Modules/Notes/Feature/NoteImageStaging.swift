import Foundation
import NotesCore

/// Puts the pictures of a note being written where Notes can read them. Notes is sandboxed, and on macOS 27 it keeps a
/// picture it gets as a data URI as a "File" attachment, but copies one given as a file URL it can read in as a picture
/// (checked 2026-10-27). The folder is AraNotch's own, inside Notes' group container, so writing there needs Full Disk
/// Access. Each write stages its own files and removes them once Notes has the note.
struct NoteImageStaging: Sendable {
    let folder: URL

    /// AraNotch's folder in Notes' group container.
    init(folder: URL = NoteStoreReader().groupContainerURL.appendingPathComponent("AraNotch", isDirectory: true)) {
        self.folder = folder
    }

    enum StagingError: Error { case unreadable(Int) }

    /// A file URL (as a string for `src`) for each image block of `document` whose file is in `files`, and the staged
    /// files to remove after the write. Throws when a picture cannot be staged: the note must not be written then.
    func stage(_ document: NoteDocument, files: [Int: URL]) throws -> (sources: [Int: String], staged: [URL]) {
        var sources: [Int: String] = [:]
        var staged: [URL] = []
        do {
            for block in document.blocks {
                guard case .image(let index) = block, sources[index] == nil else { continue }
                guard let file = files[index] else { throw StagingError.unreadable(index) }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let named = file.pathExtension.lowercased()
                let ext = named.isEmpty ? (try? Self.firstBytes(of: file)).flatMap(NoteImageFormat.fileExtension(of:)) ?? "png" : named
                let target = folder.appendingPathComponent(UUID().uuidString + "." + ext)
                if (try? FileManager.default.linkItem(at: file, to: target)) == nil {
                    try FileManager.default.copyItem(at: file, to: target)
                }
                staged.append(target)
                sources[index] = target.absoluteString
            }
        } catch {
            remove(staged)
            throw error
        }
        return (sources, staged)
    }

    func remove(_ staged: [URL]) {
        for file in staged { try? FileManager.default.removeItem(at: file) }
    }

    private static func firstBytes(of file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try handle.read(upToCount: 12) ?? Data()
    }
}
