import CryptoKit
import Foundation

/// AraNotch's own copy of note images, so a note's images can be written back without Full Disk Access
/// once they were seen. Files are named by the SHA-256 of the attachment id (ids hold "/" and ":"),
/// or by their "new-<uuid>" key for images added in AraNotch and not saved yet; the extension is kept.
/// Reading a file marks it used, and `trim` deletes the least recently used ones over the limit.
public final class NoteImageCache: @unchecked Sendable {
    private let root: URL
    private let limitBytes: Int
    private let fileManager = FileManager.default

    public init(root: URL, limitBytes: Int = 200_000_000) {
        self.root = root
        self.limitBytes = limitBytes
    }

    /// The cached file of an attachment, or nil.
    public func url(forAttachmentID id: String) -> URL? { url(forKey: id) }

    /// The cached file under an attachment id or a "new-" key, or nil.
    public func url(forKey key: String) -> URL? {
        let base = Self.fileBase(key) + "."
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        guard let name = names.first(where: { $0.hasPrefix(base) }) else { return nil }
        let url = root.appendingPathComponent(name)
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    public func store(_ data: Data, forAttachmentID id: String, fileExtension: String) throws -> URL {
        try write(data, key: id, fileExtension: fileExtension)
    }

    /// Keeps each file (in this cache) also under its id, as a hard link: the bytes are not read nor written again,
    /// and the old file stays valid for whoever still holds it. Every file is linked under a temporary name first, so
    /// files may trade ids (pictures swapped in a note) without one being removed before it is linked. Copies when a
    /// link cannot be made. Returns the new file of each id kept.
    public func link(_ files: [(file: URL, id: String)]) -> [String: URL] {
        guard (try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)) != nil else { return [:] }
        var staged: [(temporary: URL, id: String, ext: String)] = []
        for (file, id) in files {
            let ext = file.pathExtension.lowercased().isEmpty ? "png" : file.pathExtension.lowercased()
            let temporary = root.appendingPathComponent("new-" + UUID().uuidString + "." + ext)
            if (try? fileManager.linkItem(at: file, to: temporary)) != nil || (try? fileManager.copyItem(at: file, to: temporary)) != nil {
                staged.append((temporary, id, ext))
            }
        }
        var kept: [String: URL] = [:]
        for (temporary, id, ext) in staged {
            remove(key: id)
            let target = root.appendingPathComponent(Self.fileBase(id) + "." + ext)
            if (try? fileManager.moveItem(at: temporary, to: target)) != nil {
                kept[id] = target
            } else {
                try? fileManager.removeItem(at: temporary)
            }
        }
        return kept
    }

    /// Stores an image that has no attachment id yet; returns its "new-<uuid>" key.
    public func storeNew(_ data: Data, fileExtension: String) throws -> String {
        let key = "new-" + UUID().uuidString
        try write(data, key: key, fileExtension: fileExtension)
        return key
    }

    public func remove(key: String) {
        while let url = url(forKey: key) { try? fileManager.removeItem(at: url) }
    }

    /// Deletes the least recently used files until the cache is under its limit, never one in `keeping`
    /// (the files of the open note and of an edit not saved yet).
    public func trim(keeping: Set<URL> = []) {
        let kept = Set(keeping.map(\.standardizedFileURL.path))
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let files = ((try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys)) ?? []).map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return (url: url, date: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }
        var total = files.reduce(0) { $0 + $1.size }
        for file in files.sorted(by: { $0.date < $1.date }) where total > limitBytes && !kept.contains(file.url.standardizedFileURL.path) {
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }

    private func write(_ data: Data, key: String, fileExtension: String) throws -> URL {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        remove(key: key)
        let ext = fileExtension.lowercased().isEmpty ? "png" : fileExtension.lowercased()
        let url = root.appendingPathComponent(Self.fileBase(key) + "." + ext)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileBase(_ key: String) -> String {
        if key.hasPrefix("new-"), key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) { return key }
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
