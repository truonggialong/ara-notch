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
    private var accessAsks: [Bool] = []
    private var callCounts: [String: Int] = [:]
    private var launches = 0
    private var afterLaunch: NotesAccess?
    private var setBodyCount = 0
    private var lastBody: String?
    private var attachments: [String: [String]] = [:]
    private var bodyDelay: Duration = .zero
    private var readDelay: Duration = .zero
    private var readDelays: [String: Duration] = [:]
    private var bodyDateOffset: TimeInterval = 0
    private var modDelay: Duration = .zero
    private var failAfterWrite = false

    /// The next `setBody` writes, then reports a script error: a write whose outcome AraNotch cannot know.
    var nextSetBodyFailsAfterWriting: Bool {
        get { lock.withLock { failAfterWrite } }
        set { lock.withLock { failAfterWrite = newValue } }
    }

    /// How long `modification` takes, to hold a save between its check and its write.
    var modificationDelay: Duration {
        get { lock.withLock { modDelay } }
        set { lock.withLock { modDelay = newValue } }
    }

    /// How long `content` of one note takes (overrides `contentDelay`).
    func setContentDelay(_ delay: Duration, for noteID: String) { lock.withLock { readDelays[noteID] = delay } }

    /// Added to the date `setBody` returns, so two writes have clearly different dates.
    var setBodyDateOffset: TimeInterval {
        get { lock.withLock { bodyDateOffset } }
        set { lock.withLock { bodyDateOffset = newValue } }
    }

    /// How long `content` takes, to test edits made while another note opens.
    var contentDelay: Duration {
        get { lock.withLock { readDelay } }
        set { lock.withLock { readDelay = newValue } }
    }

    /// How long `setBody` takes, to test edits made while a save is in flight.
    var setBodyDelay: Duration {
        get { lock.withLock { bodyDelay } }
        set { lock.withLock { bodyDelay = newValue } }
    }

    /// Puts a note straight into a folder (which must exist), as if it was written in Notes.
    @discardableResult
    func addNote(_ name: String, in folderID: String, html: String, plainText: String, modified: Date = Date(),
                 snippet: String = "", locked: Bool = false, attachments ids: [String] = []) -> String {
        lock.withLock {
            counter += 1
            let id = "x-coredata://FAKE/ICNote/p\(counter)"
            notesByID[id] = NoteSummary(id: id, name: name, folderID: folderID, modified: modified,
                                        snippet: snippet, hasImages: !ids.isEmpty, isLocked: locked)
            contentByID[id] = NoteContent(html: html, plainText: plainText, modified: modified, attachmentCount: ids.count)
            attachments[id] = ids
            order.append(id)
            return id
        }
    }

    var setBodyCalls: Int { lock.withLock { setBodyCount } }

    /// How many calls began (counted on entry, before any delay): "content", "content:<id>", "setBody",
    /// "modification". Tests wait on these instead of sleeping for a call to be under way.
    func calls(_ key: String) -> Int { lock.withLock { callCounts[key, default: 0] } }

    private func count(_ keys: String...) { lock.withLock { for key in keys { callCounts[key, default: 0] += 1 } } }
    var lastHTML: String? { lock.withLock { lastBody } }
    var accessValue: NotesAccess {
        get { lock.withLock { accessState } }
        set { lock.withLock { accessState = newValue } }
    }

    /// Sets the attachment ids a note reports.
    func setAttachments(_ ids: [String], of noteID: String) { lock.withLock { attachments[noteID] = ids } }

    /// Changes a note's modification date, as if it was edited in Notes.
    func touch(_ id: String, to date: Date) {
        lock.withLock {
            notesByID[id]?.modified = date
            contentByID[id]?.modified = date
        }
    }

    func access(askIfNeeded: Bool) async -> NotesAccess {
        lock.withLock {
            accessAsks.append(askIfNeeded)
            return accessState
        }
    }

    /// Whether each access check asked the user.
    var accessChecks: [Bool] { lock.withLock { accessAsks } }
    var launchCalls: Int { lock.withLock { launches } }
    /// What `access` reports once `launch` has run (nil: unchanged).
    var accessAfterLaunch: NotesAccess? {
        get { lock.withLock { afterLaunch } }
        set { lock.withLock { afterLaunch = newValue } }
    }

    func launch() async {
        lock.withLock {
            launches += 1
            if let afterLaunch { accessState = afterLaunch }
        }
    }

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
        count("content", "content:\(noteID)")
        let delay = lock.withLock { readDelays[noteID] ?? readDelay }
        if delay > .zero { try await Task.sleep(for: delay) }
        return try lock.withLock {
            guard let c = contentByID[noteID] else { throw NotesServiceError.notFound }
            return c
        }
    }

    func attachmentIDs(of noteID: String) async throws -> [String] {
        try lock.withLock {
            guard contentByID[noteID] != nil else { throw NotesServiceError.notFound }
            return attachments[noteID] ?? []
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
        count("setBody")
        if setBodyDelay > .zero { try await Task.sleep(for: setBodyDelay) }
        return try lock.withLock {
            guard contentByID[noteID] != nil else { throw NotesServiceError.notFound }
            setBodyCount += 1
            lastBody = html
            let now = Date().addingTimeInterval(bodyDateOffset)
            contentByID[noteID]?.html = html
            if !html.contains("<img"), !html.contains("<object") {
                // Plain divs: their text, one line each, as Notes would report it.
                contentByID[noteID]?.plainText = html.replacingOccurrences(of: "</div>", with: "\n")
                    .replacingOccurrences(of: "<br>", with: "")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
                    .replacingOccurrences(of: "&amp;", with: "&")
            }
            contentByID[noteID]?.modified = now
            notesByID[noteID]?.modified = now
            if failAfterWrite {
                failAfterWrite = false
                throw NotesServiceError.script("timed out")
            }
            return now
        }
    }

    func modification(of noteID: String) async throws -> Date {
        count("modification")
        if modificationDelay > .zero { try await Task.sleep(for: modificationDelay) }
        return try lock.withLock {
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
