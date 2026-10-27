import Combine
import Foundation
import NotesCore
import os

/// The note shown in the editor. `images` maps an `.image` block's attachmentIndex to a file holding its bytes.
public struct OpenNote: Equatable {
    public var id: String
    public var document: NoteDocument
    public var safety: EditSafety
    /// The note's modification date when it was read or last written by AraNotch; SaveGuard compares against it.
    public var openedAt: Date
    public var images: [Int: URL]
    /// Which load this is. An editor passes it back with each edit, so an edit made on an earlier load of a note
    /// (or on another note) is never taken as this one's.
    public let generation: Int
}

public enum NoteSaveState: Equatable { case saved, pending, saving, conflict, failed(String), deleted }

/// A note just deleted (in Notes' Recently Deleted), what undo needs to put it back. `folderID` is the folder it was
/// listed in; nil when it never was, and then it cannot be put back.
struct DeletedNote: Equatable {
    var id: String
    var name: String
    var folderID: String?
}

/// The model behind the Notes page and window: folders, notes, the open note and its saving.
///
/// Every write goes through one path (`save`), which writes only when the open note is `.editable`,
/// the note was not changed elsewhere since it was read (SaveGuard), and every image's bytes are at hand
/// (the writer throws otherwise). Anything uncertain at open time makes the note read only.
@MainActor
final class NotesStore: ObservableObject {
    private static let log = Logger(subsystem: "AraNotch", category: "Notes")
    private static let recentLimit = 20
    nonisolated private static let mimeTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "heic": "image/heic",
                                    "gif": "image/gif", "tiff": "image/tiff", "tif": "image/tiff"]

    private let service: NotesService
    private let database: NoteDatabase?
    private let cache: NoteImageCache
    let staging: NoteImageStaging
    private let settings: NotesSettings
    private let debounce: Duration
    /// A note with pictures waits longer: each write sends every picture to Notes and iCloud again.
    private let imageDebounce: Duration

    @Published private(set) var access: NotesAccess = .unknown
    /// Notes' database can be read (Full Disk Access): lists of every kind and images are shown faithfully.
    @Published private(set) var fullView = false
    @Published private(set) var folders: [NoteFolder] = []
    /// Of the selected folder, newest first.
    @Published private(set) var notes: [NoteSummary] = []
    /// nil: every folder. Call `refresh()` after changing it.
    @Published var selectedFolderID: String? {
        didSet { if settings.selectedFolderID != selectedFolderID { settings.selectedFolderID = selectedFolderID } }
    }
    @Published var searchText = ""
    @Published private(set) var open: OpenNote?
    @Published private(set) var saveState: NoteSaveState = .saved
    /// The open note is being read again: it is not editable meanwhile, since what is typed would be replaced.
    @Published private(set) var isReloading = false
    /// Briefly true after an editor dropped a keystroke typed on older text, to show the other editor's newer edit.
    @Published private(set) var caughtUp = false
    private var caughtUpTask: Task<Void, Never>?

    /// The latest edit not written yet, with the load it was made on: an edit belongs to that load and is
    /// saved against its state, never against a note or a load opened later.
    private var pending: (note: OpenNote, document: NoteDocument)?
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// The note a save is writing now, if any.
    private var savingID: String?
    /// Writes per note (a write whose outcome is unknown counts too). A load notes the count it read the note at;
    /// a save from that load is allowed only while every write since was its own. Dates cannot tell this:
    /// two writes in the same second have the same date.
    private var writeCount: [String: Int] = [:]
    private var loadStamp: [Int: Int] = [:]
    private var ownWrites: [Int: Int] = [:]
    /// The load whose edit is being saved now; its image files are kept by `trim`.
    private var inFlight: OpenNote?
    /// The modification date of the last write made from each load: the base for its next save.
    private var lastWritten: [Int: Date] = [:]
    private var generationCounter = 0
    /// Only the latest requested load may become `open`.
    private var latestRequest = 0
    /// The note the latest load request is for.
    private var latestRequestID: String?
    /// Saves of each load that ended in a conflict (its edit not written). A load that replaces the open one looks
    /// whether this grew while it ran: then the open one stays, with its edit and the conflict banner.
    private var conflicts: [Int: Int] = [:]
    /// Whether each note seen in a listing is locked. Only says the note was listed: the lock state used is the one
    /// read with the note.
    private var lockedByID: [String: Bool] = [:]
    private var folderByID: [String: String] = [:]
    /// Notes making the note the open draft stands for. `flush` waits for it, so what was typed there is written.
    private var creation: Task<Void, Never>?
    /// The list row of the note deleted last, put back by undo before Notes is listed again.
    private var removedSummary: [String: NoteSummary] = [:]

    /// The id of a new note while Notes is still making it: it is open and can be typed in, and nothing is written
    /// until it has its real id.
    static let draftPrefix = "draft:"
    static func isDraft(_ id: String) -> Bool { id.hasPrefix(draftPrefix) }
    var isDraft: Bool { open.map { Self.isDraft($0.id) } ?? false }

    init(service: NotesService, database: NoteDatabase?, cache: NoteImageCache, settings: NotesSettings,
         debounce: Duration = .milliseconds(1500), imageDebounce: Duration = .seconds(5),
         staging: NoteImageStaging = NoteImageStaging()) {
        self.service = service
        self.staging = staging
        self.database = database
        self.cache = cache
        self.settings = settings
        self.debounce = debounce
        self.imageDebounce = imageDebounce
        selectedFolderID = settings.selectedFolderID
    }

    /// `notes` filtered by `searchText` in the name and snippet, ignoring case and accents.
    var visibleNotes: [NoteSummary] { Self.filter(notes, searching: searchText) }

    /// The notes whose name or snippet holds `text`, ignoring case and accents; all of them for an empty search.
    static func filter(_ notes: [NoteSummary], searching text: String) -> [NoteSummary] {
        let query = fold(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return notes }
        return notes.filter { fold($0.name).contains(query) || fold($0.snippet).contains(query) }
    }

    /// Diacritic folding leaves "đ" alone, so it is mapped by hand.
    static func fold(_ text: String) -> String {
        text.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "D")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    // MARK: Listing

    /// The only place AraNotch asks for control of Notes (the Allow button). Starts Notes first if it is closed,
    /// since macOS cannot ask about an app that is not running.
    func requestAccess() async {
        let checked = await checkAccess(askIfNeeded: true, launchingNotes: true)
        guard checked != .notRunning else {
            if access != .granted { access = .unknown }
            return
        }
        access = checked
        if access == .granted { await refresh() }
    }

    /// Lists folders and notes again. Never asks for access. `launchingNotes`: start Notes in the background when it
    /// is closed (the page or the window appears); otherwise a closed Notes leaves everything as it was, a known
    /// `.granted` included.
    func refresh(launchingNotes: Bool = false) async {
        let checked = await checkAccess(askIfNeeded: false, launchingNotes: launchingNotes)
        guard checked != .notRunning else {
            if access != .granted { access = .unknown }
            return
        }
        access = checked
        guard access == .granted else {
            if access == .denied { clearLists() }
            return
        }
        fullView = await databaseIsReadable()
        do {
            folders = try await service.folders()
            if let selected = selectedFolderID, !folders.contains(where: { $0.id == selected }) { selectedFolderID = nil }
            let list = try await service.notes(in: selectedFolderID)
            remember(list)
            notes = list
        } catch {
            handle(error, "refresh")
        }
    }

    private func checkAccess(askIfNeeded: Bool, launchingNotes: Bool) async -> NotesAccess {
        let first = await service.access(askIfNeeded: askIfNeeded)
        guard first == .notRunning, launchingNotes else { return first }
        await service.launch()
        return await service.access(askIfNeeded: askIfNeeded)
    }

    private func clearLists() {
        folders = []
        notes = []
    }

    private func remember(_ list: [NoteSummary]) {
        for note in list {
            lockedByID[note.id] = note.isLocked
            folderByID[note.id] = note.folderID
        }
    }

    /// The folder a note was last listed in, also when the list now shows another folder.
    func folderID(of id: String) -> String? { folderByID[id] }

    // MARK: Opening

    /// Saves the open note first. When that save, or a save of it made while `id` loads, ends in a conflict, the open
    /// note stays (its edit could be lost otherwise); asking again then leaves it.
    func openNote(_ id: String) async {
        let replaced = open
        let seen = replaced.map { conflicts[$0.generation, default: 0] }
        let generation = requestLoad(for: id)
        isReloading = id == replaced?.id
        await flush()
        if let replaced, conflictArose(on: replaced, since: seen) {
            if generation == latestRequest {
                isReloading = false
                latestRequestID = nil
            }
            return
        }
        await load(id, generation: generation, replacing: replaced, conflictsSeen: seen)
    }

    /// After a conflict: drops the unsaved edit of the open load and reads the note again.
    /// An edit waiting from an older load of the note is not dropped: `load` writes it first (under its own
    /// SaveGuard base and write count) and reads after it.
    func reloadOpenNote() async {
        guard let current = open, !Self.isDraft(current.id) else { return }
        let id = current.id
        // Another note is being opened (a pick, a new note): reading this one again would cancel that.
        if let requested = latestRequestID, requested != id, latestRequest > current.generation {
            Self.log.info("Not reloading the open note: another one is being opened")
            return
        }
        let generation = requestLoad(for: id)
        isReloading = true
        if pending?.note.generation == current.generation {
            debounceTask?.cancel()
            debounceTask = nil
            pending = nil
        }
        await load(id, generation: generation, replacing: current, conflictsSeen: conflicts[current.generation, default: 0])
    }

    /// Whether `note` is still the open load and one of its saves ended in a conflict since `seen` was counted.
    private func conflictArose(on note: OpenNote, since seen: Int?) -> Bool {
        guard open?.generation == note.generation, conflicts[note.generation, default: 0] > (seen ?? 0) else { return false }
        Self.log.error("A save of the note being left ended in a conflict; it stays open")
        saveState = .conflict
        return true
    }

    private func requestLoad(for id: String) -> Int {
        generationCounter += 1
        latestRequest = generationCounter
        latestRequestID = id
        return generationCounter
    }

    private struct ReadNote {
        var content: NoteContent
        var ids: [String]
        var readable: Bool
        var full: DecodedNote?
        /// The row keys of the full document's attachments, in document order.
        var attachmentKeys: [Int?]
        /// The database row is not of the moment AppleScript read: the full document may lack the last edit.
        var stale: Bool
    }

    /// `replacing`: the open load this one is to replace, with its conflict count when the request was made.
    private func load(_ id: String, generation: Int, replacing replaced: OpenNote? = nil, conflictsSeen: Int? = nil) async {
        defer {
            if generation == latestRequest {
                isReloading = false
                latestRequestID = nil  // the load is over, whatever came of it
            }
        }
        do {
            guard try await isInNotes(id) else { throw NotesServiceError.notFound }
            // A save of this note (an edit made on an earlier load) is written first, so the note read includes it;
            // when one lands while reading, the note is read again.
            var (writes, read) = try await settledRead(id)
            var attempts = 1
            while attempts < 3, savingID == id || pending?.note.id == id || writeCount[id, default: 0] != writes {
                (writes, read) = try await settledRead(id)
                attempts += 1
            }
            fullView = read.readable
            let html = NotesHTMLReader.read(html: read.content.html, plainText: read.content.plainText)
            // The lock state read with the content, not the listing's: the note may have been locked since.
            let isLocked = read.content.isLocked
            lockedByID[id] = isLocked
            let (document, composed) = Self.compose(full: read.full?.document, html: html, isLocked: isLocked,
                                                    plainText: read.content.plainText,
                                                    unsupportedFormatting: read.full?.hasUnsupportedFormatting ?? false)
            var safety = composed
            // A database that is there but cannot be read (no Full Disk Access): what a write would drop cannot be
            // seen, so every note is view only. Tests without a database are not concerned.
            if database != nil, !read.readable { safety = safety.adding(.needsFullDiskAccess) }
            if read.stale {
                Self.log.error("Notes' database does not hold the note's last change yet; opened read only")
                safety = safety.adding(.unreadable)
            }
            // With the database, AppleScript's ids are put in document order (they may come in the order added).
            let ids = read.full == nil ? read.ids : Self.ordered(read.ids, byKeys: read.attachmentKeys)
            let (images, complete) = await loadImages(of: document, ids: ids ?? [], readable: read.readable)
            // Pictures are written as files staged where Notes can read them; without that place (no Full Disk
            // Access) a note with pictures cannot be written without turning them into files.
            if !complete || (document.imageCount > 0 && !staging.isAvailable) { safety = safety.adding(.imagesUnavailable) }
            guard generation == latestRequest else {
                Self.log.info("A later open replaced this one")
                return
            }
            if let replaced, conflictArose(on: replaced, since: conflictsSeen) { return }
            if safety != .editable { Self.log.info("Note opened read only: \(String(describing: safety), privacy: .public)") }
            // Still unsettled after the last read (reads ran out, or a write landed while images loaded): what is
            // shown may lack a write, so it opens as a conflict and offers a reload instead of being edited.
            let unsettled = savingID == id || pending?.note.id == id || writeCount[id, default: 0] != writes
            loadStamp[generation] = writes
            open = OpenNote(id: id, document: document, safety: safety, openedAt: read.content.modified, images: images,
                            generation: generation)
            saveState = unsettled ? .conflict : .saved
            if unsettled { Self.log.error("Note opened while a save of it was under way; shown as a conflict") }
            addRecent(id)
        } catch {
            if case NotesServiceError.notFound = error { forget(id) }
            handle(error, "open")
            guard generation == latestRequest else { return }
            open = nil
            saveState = .saved
        }
    }

    /// Reads the note once no save of it is waiting or running; returns the write count seen before reading.
    private func settledRead(_ id: String) async throws -> (Int, ReadNote) {
        await settleSaves(of: id)
        let writes = writeCount[id, default: 0]
        let content = try await service.content(of: id)
        let ids = try await service.attachmentIDs(of: id)
        var (readable, row) = await readFull(id)
        // Notes writes its database a little after an edit: one more look a moment later.
        if Self.isStale(row, comparedWith: content.modified) {
            try? await Task.sleep(for: .milliseconds(300))
            (readable, row) = await readFull(id)
        }
        return (writes, ReadNote(content: content, ids: ids, readable: readable, full: row?.decoded,
                                 attachmentKeys: row?.attachmentKeys ?? [], stale: Self.isStale(row, comparedWith: content.modified)))
    }

    /// Whether the row's date is another second than AppleScript's (which is rounded to the second).
    /// A database without the date cannot tell, and is taken as it is.
    static func isStale(_ row: DatabaseNote?, comparedWith modified: Date) -> Bool {
        guard let rowDate = row?.modified else { return false }
        return abs(rowDate.timeIntervalSince(modified)) >= 1
    }

    private func settleSaves(of id: String) async {
        var rounds = 0
        while rounds < 5, savingID == id || pending?.note.id == id {
            rounds += 1
            if pending?.note.id == id {
                debounceTask?.cancel()
                debounceTask = nil
                startSaving()
            }
            guard let task = saveTask else { return }
            await task.value
        }
    }

    /// Whether a listing showed the note (Recently Deleted is never listed). Looks through every folder when no
    /// listing has shown it yet.
    private func isInNotes(_ id: String) async throws -> Bool {
        if lockedByID[id] != nil { return true }
        remember(try await service.notes(in: nil))
        return lockedByID[id] != nil
    }

    private func databaseIsReadable() async -> Bool {
        guard let database else { return false }
        return await Task.detached { database.isReadable }.value
    }

    /// Whether the database is readable, and the note's row from it.
    private func readFull(_ id: String) async -> (Bool, DatabaseNote?) {
        guard let database else { return (false, nil) }
        let key = NotesIDs.databaseKey(of: id, entity: "ICNote")
        return await Task.detached {
            guard database.isReadable else { return (false, nil) }
            return (true, key.flatMap { database.note(forNoteKey: $0) })
        }.value
    }

    /// The document to show (`full ?? html`) and its safety. A table of the full document takes its HTML from the
    /// AppleScript document's table at the same attachment position; without one the note is unreadable.
    static func compose(full: NoteDocument?, html: NoteDocument, isLocked: Bool, plainText: String,
                        unsupportedFormatting: Bool = false) -> (NoteDocument, EditSafety) {
        var safety = EditSafety.check(full: full, html: html, isLocked: isLocked, plainText: plainText,
                                      unsupportedFormatting: unsupportedFormatting)
        guard var document = full else { return (html, safety) }
        var htmlTables: [Int: NoteBlock] = [:]
        for (slot, block) in attachmentBlocks(html) { if case .table = block { htmlTables[slot] = block } }
        for (position, (slot, block)) in zip(attachmentPositions(document), attachmentBlocks(document)) {
            guard case .table(let tableHTML, _) = block, tableHTML.isEmpty else { continue }
            if case .table(let found, let cells)? = htmlTables[slot], !found.isEmpty {
                document.blocks[position] = .table(html: found, cells: cells)
            } else {
                safety = safety.adding(.unreadable)
            }
        }
        return (document, safety)
    }

    /// The attachment blocks (image, table, file, drawing) with their position among the note's attachments.
    nonisolated static func attachmentBlocks(_ document: NoteDocument) -> [(slot: Int, block: NoteBlock)] {
        document.blocks.filter(isAttachment).enumerated().map { ($0.offset, $0.element) }
    }

    private static func attachmentPositions(_ document: NoteDocument) -> [Int] {
        document.blocks.indices.filter { isAttachment(document.blocks[$0]) }
    }

    nonisolated private static func isAttachment(_ block: NoteBlock) -> Bool {
        switch block {
        case .image, .table, .file, .drawing: return true
        default: return false
        }
    }

    /// AppleScript's attachment ids in the order of `keys` (the database's document order), or nil when they are not
    /// the same attachments: then no image can be placed for sure.
    static func ordered(_ ids: [String], byKeys keys: [Int?]) -> [String]? {
        guard ids.count == keys.count else { return nil }
        var byKey: [Int: String] = [:]
        for id in ids {
            guard let key = NotesIDs.attachmentKey(of: id), byKey[key] == nil else { return nil }
            byKey[key] = id
        }
        let ordered = keys.compactMap { $0.flatMap { byKey[$0] } }
        return ordered.count == ids.count ? ordered : nil
    }

    /// Each image's file, from the cache or else copied from Notes' media. `complete` is false when an image has
    /// no bytes, or when the attachment ids do not line up with the document (an image could be swapped).
    private func loadImages(of document: NoteDocument, ids: [String], readable: Bool) async -> ([Int: URL], complete: Bool) {
        let slots = Self.attachmentBlocks(document)
        let imageSlots = slots.compactMap { item -> (slot: Int, index: Int)? in
            if case .image(let index) = item.block { return (item.slot, index) }
            return nil
        }
        guard !imageSlots.isEmpty else { return ([:], true) }
        guard ids.count == slots.count, imageSlots.allSatisfy({ $0.slot == $0.index }) else {
            Self.log.error("Attachment ids do not line up with the note: \(ids.count) ids, \(slots.count) attachments")
            return ([:], false)
        }
        var images: [Int: URL] = [:]
        var complete = true
        for (_, index) in imageSlots where images[index] == nil {
            let id = ids[index]
            if let url = cache.url(forAttachmentID: id) {
                images[index] = url
            } else if readable, let url = await copyFromDatabase(id) {
                images[index] = url
            } else {
                complete = false
            }
        }
        // Trimmed after the lookup, so the files this note is about to use are kept too.
        let inUse = [open, pending?.note, inFlight].compactMap { $0 }.flatMap { Array($0.images.values) }
        cache.trim(keeping: Set(inUse + Array(images.values)))
        return (images, complete)
    }

    private func copyFromDatabase(_ id: String) async -> URL? {
        guard let database, let key = NotesIDs.attachmentKey(of: id) else { return nil }
        let found: (Data, String)? = await Task.detached {
            guard let file = database.attachmentFile(forAttachmentKey: key) else { return nil }
            guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
            // A picture Notes got through HTML is in a file with no extension: its bytes tell its type.
            let named = file.pathExtension.lowercased()
            // An unknown type could not be embedded with the right MIME type.
            guard let ext = Self.mimeTypes[named] != nil ? named : NoteImageFormat.fileExtension(of: data) else { return nil }
            return (data, ext)
        }.value
        guard let (data, ext) = found else { return nil }
        do {
            return try cache.store(data, forAttachmentID: id, fileExtension: ext)
        } catch {
            Self.log.error("Could not cache an image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func addRecent(_ id: String) {
        var recent = settings.recentIDs.filter { $0 != id }
        recent.insert(id, at: 0)
        settings.recentIDs = Array(recent.prefix(Self.recentLimit))
    }

    private func forget(_ id: String) {
        notes.removeAll { $0.id == id }
        lockedByID[id] = nil
        if settings.recentIDs.contains(id) { settings.recentIDs.removeAll { $0 == id } }
    }

    // MARK: Editing

    /// Adds an image the user put in the open note and returns the attachmentIndex for its `.image` block,
    /// or nil when the note is not editable or the bytes could not be kept.
    func addImage(_ data: Data, fileExtension: String) -> Int? {
        guard var note = open, note.safety == .editable, !data.isEmpty, staging.isAvailable,
              Self.mimeTypes[fileExtension.lowercased()] != nil else { return nil }
        do {
            let key = try cache.storeNew(data, fileExtension: fileExtension)
            guard let url = cache.url(forKey: key) else { return nil }
            let used = note.document.blocks.compactMap { block -> Int? in
                switch block {
                case .image(let i), .file(let i, _, _), .drawing(let i): return i
                default: return nil
                }
            } + Array(note.images.keys) + [Self.attachmentBlocks(note.document).count - 1]
            let index = (used.max() ?? -1) + 1
            note.images[index] = url
            open = note
            return index
        } catch {
            Self.log.error("Could not keep a new image: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Takes the editor's document and saves it once typing stops. `generation` is the one of the `OpenNote` the
    /// editor was built from; an edit from another load, or for a note that may not be written, is ignored.
    func edit(_ document: NoteDocument, generation: Int) {
        guard var note = open, note.generation == generation else {
            Self.log.error("Ignored an edit made on another load")
            return
        }
        guard note.safety == .editable else { return }
        note.document = document
        open = note
        // After a conflict or deletion nothing is written again; the user reloads or makes a new note. A draft Notes
        // could not make keeps its text on screen, and its failure, to be copied.
        guard saveState != .conflict, saveState != .deleted else { return }
        if Self.isDraft(note.id), creation == nil { return }
        pending = (note, document)
        saveState = .pending
        debounceTask?.cancel()
        // Leaving the page, closing the window or the notch, and quitting save at once (`flush`) all the same.
        let wait = document.imageCount > 0 ? imageDebounce : debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.startSaving()
        }
    }

    /// Shows the "updated from the other window" note for two seconds.
    func noteCaughtUp() {
        caughtUp = true
        caughtUpTask?.cancel()
        caughtUpTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.caughtUp = false
        }
    }

    /// Saves now if an edit is waiting, and returns once nothing is being saved.
    func flush() async {
        debounceTask?.cancel()
        debounceTask = nil
        if let creation { await creation.value }
        startSaving()
        while let task = saveTask { await task.value }
    }

    /// A draft's edit waits until Notes made the note (`finishCreating` starts it then).
    private func startSaving() {
        guard saveTask == nil, let waiting = pending, !Self.isDraft(waiting.note.id) else { return }
        saveTask = Task { [weak self] in
            await self?.saveLoop()
            self?.saveTask = nil
        }
    }

    /// Writes the pending edit, then any edit made meanwhile, one at a time.
    /// The save state belongs to the open load; the save of an edit from an earlier load is only logged.
    private func saveLoop() async {
        while let (note, document) = pending {
            pending = nil
            let isOpen = { [weak self] in self?.open?.generation == note.generation }
            if isOpen() { saveState = .saving }
            inFlight = note
            let result = await save(document, of: note)
            inFlight = nil
            if result != .saved { Self.log.error("Note not saved: \(String(describing: result), privacy: .public)") }
            if result == .conflict { conflicts[note.generation, default: 0] += 1 }
            guard isOpen() else { continue }
            if result == .saved {
                saveState = pending == nil ? .saved : .pending
            } else {
                saveState = result
                if pending?.note.generation == note.generation { pending = nil }
                return
            }
        }
    }

    /// The only place a note is written. `edited` is the load the edit was made on, as it was then. While that load
    /// is still open its current state (images moved by an earlier save) is used; the SaveGuard base is the last
    /// write made from that load, or the date it was read. Nothing of a newer load is touched.
    private func save(_ document: NoteDocument, of edited: OpenNote) async -> NoteSaveState {
        let id = edited.id
        let generation = edited.generation
        savingID = id
        defer { savingID = nil }
        do {
            let note = open?.generation == generation ? open ?? edited : edited
            guard note.safety == .editable else { return .failed("The note may not be written") }
            // Staging the pictures where Notes can read them and building the HTML is done off the main actor, and
            // before the date check, so no more than that check stands between reading the date and writing.
            let files = note.images
            let (html, staged) = try await Self.html(for: document, files: files, staging: staging)
            defer { staging.remove(staged) }
            let current = try await service.modification(of: id)
            let base = lastWritten[generation] ?? edited.openedAt
            if SaveGuard.decide(openedAt: base, currentModification: current) == .conflict { return .conflict }
            // No await between this check and the write: saves run one at a time.
            guard writeCount[id, default: 0] == (loadStamp[generation] ?? -1) + ownWrites[generation, default: 0] else {
                Self.log.error("Note was written from another load since this one read it")
                return .conflict
            }
            let modified: Date
            do {
                modified = try await service.setBody(html, of: id)
            } catch NotesServiceError.notFound {
                throw NotesServiceError.notFound
            } catch NotesServiceError.denied {
                throw NotesServiceError.denied
            } catch {
                // The write may or may not have happened: count it as someone else's, so no load writes over it.
                noteWritten(id, by: nil)
                throw error
            }
            lastWritten[generation] = modified
            noteWritten(id, by: generation)
            guard open?.generation == generation else { return .saved }
            open?.openedAt = modified
            await keepImages(of: document, files: files, noteID: id, generation: generation)
            return .saved
        } catch NotesServiceError.notFound {
            return .deleted
        } catch NotesServiceError.denied {
            access = .denied
            return .failed(String(describing: NotesServiceError.denied))
        } catch {
            Self.log.error("Save failed: \(String(describing: error), privacy: .public)")
            return .failed(String(describing: error))
        }
    }

    /// Counts a write of `id`; `generation` nil when its outcome is unknown. An open load of the same note other
    /// than the writer now shows stale text, so it is marked a conflict at once.
    private func noteWritten(_ id: String, by generation: Int?) {
        writeCount[id, default: 0] += 1
        if let generation { ownWrites[generation, default: 0] += 1 }
        if let open, open.id == id, open.generation != generation {
            saveState = .conflict
            if pending?.note.generation == open.generation {
                pending = nil
                conflicts[open.generation, default: 0] += 1
            }
        }
    }

    /// The HTML of `document`, its pictures staged as files Notes can read, and those files, to remove once written.
    /// Throws, staging nothing, when a picture cannot be staged.
    nonisolated private static func html(for document: NoteDocument, files: [Int: URL],
                                         staging: NoteImageStaging) async throws -> (String, [URL]) {
        try await Task.detached {
            let staged = try staging.stage(document, files: files)
            do {
                return (try NotesHTMLWriter.write(document, imageSources: staged.sources), staged.staged)
            } catch {
                staging.remove(staged.staged)
                throw error
            }
        }.value
    }

    /// Notes gives written images new attachment ids: the cache keeps their files under those ids too (linked, the
    /// bytes are not written again), so they are at hand for the next write without the database. The open document
    /// keeps its own indexes (an editor holding them stays right); only the files behind them move. Skipped when the
    /// ids do not line up.
    private func keepImages(of document: NoteDocument, files: [Int: URL], noteID: String, generation: Int) async {
        guard document.imageCount > 0 else { return }
        let ids: [String]
        do { ids = try await service.attachmentIDs(of: noteID) } catch {
            Self.log.error("No attachment ids after a save: \(String(describing: error), privacy: .public)")
            return
        }
        let slots = Self.attachmentBlocks(document)
        guard ids.count == slots.count else {
            Self.log.error("Saved note has \(ids.count) attachment ids for \(slots.count) attachments; images not re-keyed")
            return
        }
        var pairs: [(file: URL, id: String)] = []
        var indexOfID: [String: Int] = [:]
        for (slot, block) in slots {
            guard case .image(let index) = block, let file = files[index] else { continue }
            pairs.append((file, ids[slot]))
            indexOfID[ids[slot]] = index
        }
        var moved: [Int: URL] = [:]
        for (id, url) in cache.link(pairs) { if let index = indexOfID[id] { moved[index] = url } }
        // A reload while the ids were read has its own indexes: these files must not be put behind them.
        guard var note = open, note.generation == generation else { return }
        for (index, url) in moved { note.images[index] = url }  // "new-" files left behind go with trim
        open = note
    }

    // MARK: Creating and deleting

    /// Makes a note in `folderID` (nil: the default folder, or the first one) and opens it. `document` re-creates a
    /// note's content, for instance after a conflict; its images come from the open note.
    ///
    /// The note opens at once as a draft and `opened` is called then (the page puts the caret in it); Notes makes the
    /// note meanwhile, which may take seconds. Returns once Notes made it, or failed to.
    func newNote(_ document: NoteDocument? = nil, in folderID: String? = nil, opened: (() -> Void)? = nil) async {
        let imageFiles = open?.images ?? [:]  // the document's indexes are those of the load open now
        await flush()
        // Right after login Notes may be closed and nothing listed yet: it is started rather than nothing made.
        if folders.isEmpty { await refresh(launchingNotes: true) }
        guard let folder = folders.first(where: { $0.id == folderID }) ?? folders.first(where: { $0.id == settings.defaultFolderID })
                ?? folders.first else {
            Self.log.error("No folder to make a note in")
            return
        }
        let document = document ?? NoteDocument(blocks: [.paragraph([])])
        let draftID = Self.draftPrefix + UUID().uuidString
        let generation = requestLoad(for: draftID)
        latestRequestID = nil  // nothing is read for it
        loadStamp[generation] = 0
        // As a note read back would be: view only without Full Disk Access, or with pictures that cannot be staged.
        var safety = EditSafety.editable
        if database != nil, !fullView { safety = safety.adding(.needsFullDiskAccess) }
        if document.imageCount > 0, !staging.isAvailable { safety = safety.adding(.imagesUnavailable) }
        folderByID[draftID] = folder.id
        isReloading = false
        open = OpenNote(id: draftID, document: document, safety: safety, openedAt: Date(), images: imageFiles,
                        generation: generation)
        saveState = .saved
        opened?()
        let task = Task { await finishCreating(draftID, generation: generation, document: document, files: imageFiles,
                                               in: folder.id) }
        creation = task
        await task.value
        if creation == task { creation = nil }
    }

    /// Has Notes make the draft's note, then gives the draft (open, or only its waiting edit when another note was
    /// opened meanwhile) the note's id and date, and writes what was typed meanwhile. On failure the draft stays,
    /// its text on screen, with the failure.
    private func finishCreating(_ draftID: String, generation: Int, document: NoteDocument, files: [Int: URL],
                                in folderID: String) async {
        do {
            let (html, staged) = try await Self.html(for: document, files: files, staging: staging)
            defer { staging.remove(staged) }
            let id = try await service.create(in: folderID, html: html)
            let modified = try await service.modification(of: id)
            folderByID[id] = folderID
            folderByID[draftID] = nil
            if open?.generation == generation {
                open?.id = id
                open?.openedAt = modified
            }
            if pending?.note.generation == generation {
                pending?.note.id = id
                pending?.note.openedAt = modified
            }
            addRecent(id)
            await refresh()
            startSaving()
        } catch {
            handle(error, "create")
            if open?.generation == generation { saveState = .failed(String(describing: error)) }
            if pending?.note.generation == generation { pending = nil }
        }
    }

    /// Makes a folder (in Notes' default account), lists again and selects it. Returns nil for an empty name or
    /// when Notes refused.
    @discardableResult
    func createFolder(named name: String) async -> NoteFolder? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        do {
            let folder = try await service.createFolder(named: name)
            selectedFolderID = folder.id
            await refresh()
            return folder
        } catch {
            handle(error, "create folder")
            return nil
        }
    }

    /// Deletes a note (Notes moves it to Recently Deleted), after saving what was typed in it, so undo brings it all
    /// back. The note leaves the list and the editor before Notes is asked, which may take seconds; `started` is
    /// told then, with what undo needs. Returns that, or nil when Notes did not delete it (the note is listed, and
    /// opened, again).
    @discardableResult
    func delete(_ id: String, started: ((DeletedNote) -> Void)? = nil) async -> DeletedNote? {
        await flush()
        let summary = notes.first { $0.id == id }
        let wasOpen = open?.id == id
        let typedName = wasOpen ? open?.document.plainText.split(separator: "\n").first
            .map { $0.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespaces) } : nil
        let name = typedName.flatMap { $0.isEmpty ? nil : $0 } ?? summary?.name ?? ""
        let deleted = DeletedNote(id: id, name: name, folderID: folderByID[id])
        removedSummary = summary.map { [id: $0] } ?? [:]
        forget(id)
        if wasOpen {
            open = nil
            saveState = .saved
        }
        started?(deleted)
        do {
            try await service.delete(id)
        } catch NotesServiceError.notFound {
            // Already gone.
        } catch {
            handle(error, "delete")
            await refresh()
            if wasOpen, open == nil { await openNote(id) }
            return nil
        }
        return deleted
    }

    /// Puts a deleted note back in the folder it was listed in, shows it in the list and, when nothing else is open,
    /// in the editor, then lists again. False when its folder is not known or Notes refused.
    func undoDelete(_ deleted: DeletedNote) async -> Bool {
        guard let folderID = deleted.folderID else { return false }
        do {
            try await service.restore(deleted.id, to: folderID)
        } catch {
            handle(error, "undo delete")
            return false
        }
        folderByID[deleted.id] = folderID
        if var summary = removedSummary.removeValue(forKey: deleted.id), selectedFolderID == nil || selectedFolderID == folderID {
            summary.folderID = folderID
            lockedByID[deleted.id] = summary.isLocked
            notes.append(summary)
            notes.sort { $0.modified > $1.modified }
        }
        if open == nil { await openNote(deleted.id) }
        await refresh()
        return true
    }

    /// Opens a note in the Notes app: for a note AraNotch only shows (locked, or read only).
    func showInNotes(_ id: String) async {
        do {
            try await service.show(id)
        } catch {
            if case NotesServiceError.notFound = error { forget(id) }
            handle(error, "show")
        }
    }

    private func handle(_ error: Error, _ action: String) {
        if case NotesServiceError.denied = error { access = .denied }
        Self.log.error("Notes \(action, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    }
}
