import Carbon
import Foundation

/// Talks to the Notes app through AppleScript. Scripts run one at a time on a private queue, because
/// `NSAppleScript` is not thread safe and Notes handles one Apple event at a time anyway.
public final class NotesBridge: NotesService {
    private static let notesBundleID = "com.apple.Notes"
    private static let snippetLimit = 50
    private static let snippetLength = 120

    private let queue = DispatchQueue(label: "com.aranotch.notes.applescript")

    public init() {}

    // MARK: Permission

    public func access(askIfNeeded: Bool) async -> NotesAccess {
        await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: Self.notesBundleID)
                guard let desc = target.aeDesc else { return continuation.resume(returning: .unknown) }
                let status = AEDeterminePermissionToAutomateTarget(
                    desc, AEEventClass(typeWildCard), AEEventID(typeWildCard), askIfNeeded)
                switch status {
                case OSStatus(noErr): continuation.resume(returning: .granted)
                case OSStatus(errAEEventNotPermitted): continuation.resume(returning: .denied)
                // Notes is not running, or the user was not asked yet.
                default: continuation.resume(returning: .unknown)
                }
            }
        }
    }

    // MARK: Reading

    public func folders() async throws -> [NoteFolder] {
        try await run(NotesScripts.listFolders()) { result in
            Self.indices(of: result).compactMap { i in
                guard let row = result.atIndex(i) else { return nil }
                guard let id = row.atIndex(1)?.stringValue, let name = row.atIndex(2)?.stringValue,
                      !NotesScripts.trashFolderNames.contains(name) else { return nil }
                return NoteFolder(id: id, name: name, account: row.atIndex(3)?.stringValue ?? "",
                                  noteCount: Int(row.atIndex(4)?.int32Value ?? 0))
            }
        }
    }

    public func notes(in folderID: String?) async throws -> [NoteSummary] {
        var notes: [NoteSummary] = try await run(NotesScripts.listNotes(folderID: folderID)) { result in
            var out: [NoteSummary] = []
            for i in Self.indices(of: result) {
                guard let row = result.atIndex(i), let fid = row.atIndex(1)?.stringValue,
                      let ids = row.atIndex(2), let names = row.atIndex(3),
                      let dates = row.atIndex(4), let locks = row.atIndex(5) else { continue }
                for j in Self.indices(of: ids) {
                    guard let id = ids.atIndex(j)?.stringValue else { continue }
                    guard let date = dates.atIndex(j)?.dateValue else { throw NotesServiceError.script("bad date") }
                    out.append(NoteSummary(
                        id: id, name: names.atIndex(j)?.stringValue ?? "", folderID: fid,
                        modified: date, snippet: "",
                        hasImages: false, isLocked: locks.atIndex(j)?.booleanValue ?? false))
                }
            }
            return out
        }
        notes.sort { $0.modified > $1.modified }

        // Snippets and image flags only for the newest ones: each needs a call per note in Notes.
        let newest = notes.prefix(Self.snippetLimit).filter { !$0.isLocked }
        guard !newest.isEmpty else { return notes }
        let details: [(String, Int)] = try await run(NotesScripts.snippets(noteIDs: newest.map(\.id))) { result in
            Self.indices(of: result).map { i in
                let row = result.atIndex(i)
                return (row?.atIndex(1)?.stringValue ?? "", Int(row?.atIndex(2)?.int32Value ?? 0))
            }
        }
        var byID: [String: (String, Int)] = [:]
        for (note, detail) in zip(newest, details) { byID[note.id] = detail }
        for i in notes.indices {
            guard let (text, attachments) = byID[notes[i].id] else { continue }
            notes[i].snippet = Self.snippet(from: text, title: notes[i].name)
            notes[i].hasImages = attachments > 0
        }
        return notes
    }

    public func content(of noteID: String) async throws -> NoteContent {
        try await run(NotesScripts.content(noteID: noteID)) { result in
            NoteContent(html: result.atIndex(1)?.stringValue ?? "", plainText: result.atIndex(2)?.stringValue ?? "",
                        modified: try Self.date(result.atIndex(3)),
                        attachmentCount: Int(result.atIndex(4)?.int32Value ?? 0))
        }
    }

    public func modification(of noteID: String) async throws -> Date {
        try await run(NotesScripts.modification(noteID: noteID)) { try Self.date($0) }
    }

    public func attachmentIDs(of noteID: String) async throws -> [String] {
        try await run(NotesScripts.attachmentIDs(noteID: noteID)) { result in
            // One attachment comes back as a bare string, none as an empty list.
            if result.numberOfItems == 0 { return result.stringValue.map { [$0] } ?? [] }
            return Self.indices(of: result).compactMap { result.atIndex($0)?.stringValue }
        }
    }

    // MARK: Writing

    public func create(in folderID: String, html: String) async throws -> String {
        try await withHTMLFile(html) { path in
            try await run(NotesScripts.create(folderID: folderID, htmlPath: path)) { result in
                guard let id = result.stringValue else { throw NotesServiceError.script("Notes returned no note id") }
                return id
            }
        }
    }

    public func setBody(_ html: String, of noteID: String) async throws -> Date {
        try await withHTMLFile(html) { path in
            try await run(NotesScripts.setBody(noteID: noteID, htmlPath: path)) { try Self.date($0) }
        }
    }

    public func delete(_ noteID: String) async throws {
        try await run(NotesScripts.delete(noteID: noteID)) { _ in () }
    }

    public func createFolder(named name: String) async throws -> NoteFolder {
        try await run(NotesScripts.createFolder(named: name)) { result in
            guard let id = result.atIndex(1)?.stringValue else { throw NotesServiceError.script("Notes returned no folder id") }
            return NoteFolder(id: id, name: result.atIndex(2)?.stringValue ?? name,
                              account: result.atIndex(3)?.stringValue ?? "", noteCount: 0)
        }
    }

    public func show(_ noteID: String) async throws {
        try await run(NotesScripts.show(noteID: noteID)) { _ in () }
    }

    // MARK: Running scripts

    /// Runs `source` on the script queue and reads the result there (descriptors are not Sendable).
    private func run<T: Sendable>(_ source: String, _ parse: @escaping @Sendable (NSAppleEventDescriptor) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                guard let script = NSAppleScript(source: source) else {
                    return continuation.resume(throwing: NotesServiceError.script("The script did not compile"))
                }
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    return continuation.resume(throwing: Self.error(from: errorInfo))
                }
                continuation.resume(with: Result { try parse(result) })
            }
        }
    }

    /// Writes `html` to a temporary UTF-8 file for the script to read, and removes it afterwards.
    private func withHTMLFile<T>(_ html: String, _ body: (String) async throws -> T) async throws -> T {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AraNotchNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(UUID().uuidString + ".html")
        try Data(html.utf8).write(to: file, options: .atomic)
        defer { try? FileManager.default.removeItem(at: file) }
        return try await body(file.path)
    }

    private static func error(from info: NSDictionary) -> NotesServiceError {
        let number = (info[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (info[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
        switch number {
        case -1743: return .denied
        case -1728: return .notFound
        default: return .script("\(message) (\(number))")
        }
    }

    /// A modification date, or an error: a made-up date would defeat SaveGuard.
    private static func date(_ descriptor: NSAppleEventDescriptor?) throws -> Date {
        guard let date = descriptor?.dateValue else { throw NotesServiceError.script("bad date") }
        return date
    }

    /// 1-based indices of a list descriptor (empty for an empty list).
    private static func indices(of list: NSAppleEventDescriptor) -> [Int] {
        list.numberOfItems > 0 ? Array(1...list.numberOfItems) : []
    }

    /// The first 120 characters after the title line, on one line.
    static func snippet(from plainText: String, title: String) -> String {
        var lines = plainText.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        if lines.first == title.trimmingCharacters(in: .whitespaces) || lines.first?.isEmpty == true { lines.removeFirst() }
        let joined = lines.filter { !$0.isEmpty }.joined(separator: " ")
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .trimmingCharacters(in: .whitespaces)
        return String(joined.prefix(snippetLength))
    }
}
