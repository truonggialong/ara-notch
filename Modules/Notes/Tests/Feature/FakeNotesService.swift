import Foundation
@testable import NotesFeature

/// An in-memory Notes for tests: folders and notes, counted writes, settable modification dates and access.
final class FakeNotesService: NotesService, @unchecked Sendable {
    private let lock = NSLock()
    private var folderList: [NoteFolder] = []
    private var notesByID: [String: NoteSummary] = [:]
    private var contentByID: [String: NoteContent] = [:]
    private var order: [String] = []
    private var counter = 0
    private var accessState: NotesAccess = .granted
    private var setBodyCount = 0
    private var lastBody: String?
    private var savedAttachments: [(index: Int, noteID: String, url: URL)] = []

    var setBodyCalls: Int { lock.withLock { setBodyCount } }
    var lastHTML: String? { lock.withLock { lastBody } }
    var attachmentSaves: [(index: Int, noteID: String, url: URL)] { lock.withLock { savedAttachments } }
    var accessValue: NotesAccess {
        get { lock.withLock { accessState } }
        set { lock.withLock { accessState = newValue } }
    }

    /// Changes a note's modification date, as if it was edited in Notes.
    func touch(_ id: String, to date: Date) {
        lock.withLock {
            notesByID[id]?.modified = date
            contentByID[id]?.modified = date
        }
    }

    func access(askIfNeeded: Bool) async -> NotesAccess { accessValue }

    func folders() async throws -> [NoteFolder] {
        lock.withLock {
            folderList.map { folder in
                var f = folder
                f.noteCount = notesByID.values.filter { $0.folderID == folder.id }.count
                return f
            }
        }
    }

    func notes(in folderID: String?) async throws -> [NoteSummary] {
        lock.withLock {
            order.compactMap { notesByID[$0] }
                .filter { folderID == nil || $0.folderID == folderID }
                .sorted { $0.modified > $1.modified }
        }
    }

    func content(of noteID: String) async throws -> NoteContent {
        try lock.withLock {
            guard let c = contentByID[noteID] else { throw NotesServiceError.notFound }
            return c
        }
    }

    func saveAttachment(_ index: Int, of noteID: String, to url: URL) async throws {
        try lock.withLock {
            guard contentByID[noteID] != nil else { throw NotesServiceError.notFound }
            savedAttachments.append((index, noteID, url))
        }
    }

    func create(in folderID: String, html: String) async throws -> String {
        try lock.withLock {
            guard folderList.contains(where: { $0.id == folderID }) else { throw NotesServiceError.notFound }
            counter += 1
            let id = "x-coredata://FAKE/ICNote/p\(counter)"
            let now = Date()
            notesByID[id] = NoteSummary(id: id, name: "Note \(counter)", folderID: folderID, modified: now,
                                        snippet: "", hasImages: false, isLocked: false)
            contentByID[id] = NoteContent(html: html, plainText: "", modified: now, attachmentCount: 0)
            order.append(id)
            return id
        }
    }

    func setBody(_ html: String, of noteID: String) async throws -> Date {
        try lock.withLock {
            guard contentByID[noteID] != nil else { throw NotesServiceError.notFound }
            setBodyCount += 1
            lastBody = html
            let now = Date()
            contentByID[noteID]?.html = html
            contentByID[noteID]?.modified = now
            notesByID[noteID]?.modified = now
            return now
        }
    }

    func modification(of noteID: String) async throws -> Date {
        try lock.withLock {
            guard let n = notesByID[noteID] else { throw NotesServiceError.notFound }
            return n.modified
        }
    }

    func delete(_ noteID: String) async throws {
        try lock.withLock {
            guard notesByID.removeValue(forKey: noteID) != nil else { throw NotesServiceError.notFound }
            contentByID[noteID] = nil
            order.removeAll { $0 == noteID }
        }
    }

    func createFolder(named name: String) async throws -> NoteFolder {
        lock.withLock {
            counter += 1
            let folder = NoteFolder(id: "x-coredata://FAKE/ICFolder/p\(counter)", name: name, account: "iCloud", noteCount: 0)
            folderList.append(folder)
            return folder
        }
    }

    func show(_ noteID: String) async throws {
        try lock.withLock { if notesByID[noteID] == nil { throw NotesServiceError.notFound } }
    }
}
