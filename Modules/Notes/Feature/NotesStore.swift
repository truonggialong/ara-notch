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
    private let settings: NotesSettings
    private let debounce: Duration

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
    /// Whether each note seen in a listing is locked.
    private var lockedByID: [String: Bool] = [:]

    init(service: NotesService, database: NoteDatabase?, cache: NoteImageCache, settings: NotesSettings,
         debounce: Duration = .milliseconds(1500)) {
        self.service = service
        self.database = database
        self.cache = cache
        self.settings = settings
        self.debounce = debounce
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
        for note in list { lockedByID[note.id] = note.isLocked }
    }

    // MARK: Opening

    func openNote(_ id: String) async {
        let generation = requestLoad()
        await flush()
        await load(id, generation: generation)
    }

    /// After a conflict: drops the unsaved edit of the open load and reads the note again.
    /// An edit waiting from an older load of the note is not dropped: `load` writes it first (under its own
    /// SaveGuard base and write count) and reads after it.
    func reloadOpenNote() async {
        guard let current = open else { return }
        let id = current.id
        let generation = requestLoad()
        if pending?.note.generation == current.generation {
            debounceTask?.cancel()
            debounceTask = nil
            pending = nil
        }
        await load(id, generation: generation)
    }

    private func requestLoad() -> Int {
        generationCounter += 1
        latestRequest = generationCounter
        return generationCounter
    }

    private struct ReadNote {
        var content: NoteContent
        var ids: [String]
        var readable: Bool
        var full: NoteDocument?
    }

    private func load(_ id: String, generation: Int) async {
        do {
            guard let isLocked = try await lockedState(of: id) else { throw NotesServiceError.notFound }
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
            let (document, composed) = Self.compose(full: read.full, html: html, isLocked: isLocked,
                                                    plainText: read.content.plainText)
            var safety = composed
            let (images, complete) = await loadImages(of: document, ids: read.ids, readable: read.readable)
            if !complete { safety = safety.adding(.imagesUnavailable) }
            guard generation == latestRequest else {
                Self.log.info("A later open replaced this one")
                return
            }
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
        let (readable, full) = await readFull(id)
        return (writes, ReadNote(content: content, ids: ids, readable: readable, full: full))
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

    /// nil when the note is not in Notes. Looks through every folder when no listing has shown it yet.
    private func lockedState(of id: String) async throws -> Bool? {
        if let known = lockedByID[id] { return known }
        remember(try await service.notes(in: nil))
        return lockedByID[id]
    }

    private func databaseIsReadable() async -> Bool {
        guard let database else { return false }
        return await Task.detached { database.isReadable }.value
    }

    /// Whether the database is readable, and the note's document from it.
    private func readFull(_ id: String) async -> (Bool, NoteDocument?) {
        guard let database else { return (false, nil) }
        let key = NotesIDs.databaseKey(of: id, entity: "ICNote")
        return await Task.detached {
            guard database.isReadable else { return (false, nil) }
            return (true, key.flatMap { database.document(forNoteKey: $0)?.document })
        }.value
    }

    /// The document to show (`full ?? html`) and its safety. A table of the full document takes its HTML from the
    /// AppleScript document's table at the same attachment position; without one the note is unreadable.
    static func compose(full: NoteDocument?, html: NoteDocument, isLocked: Bool, plainText: String) -> (NoteDocument, EditSafety) {
        var safety = EditSafety.check(full: full, html: html, isLocked: isLocked, plainText: plainText)
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
    static func attachmentBlocks(_ document: NoteDocument) -> [(slot: Int, block: NoteBlock)] {
        document.blocks.filter(isAttachment).enumerated().map { ($0.offset, $0.element) }
    }

    private static func attachmentPositions(_ document: NoteDocument) -> [Int] {
        document.blocks.indices.filter { isAttachment(document.blocks[$0]) }
    }

    private static func isAttachment(_ block: NoteBlock) -> Bool {
        switch block {
        case .image, .table, .file, .drawing: return true
        default: return false
        }
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
            let ext = file.pathExtension.lowercased()
            // An unknown type could not be embedded with the right MIME type.
            guard Self.mimeTypes[ext] != nil, let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
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
        guard var note = open, note.safety == .editable, !data.isEmpty,
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
        // After a conflict or deletion nothing is written again; the user reloads or makes a new note.
        guard saveState != .conflict, saveState != .deleted else { return }
        pending = (note, document)
        saveState = .pending
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
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
        startSaving()
        while let task = saveTask { await task.value }
    }

    private func startSaving() {
        guard saveTask == nil, pending != nil else { return }
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
            let current = try await service.modification(of: id)
            let note = open?.generation == generation ? open ?? edited : edited
            guard note.safety == .editable else { return .failed("The note may not be written") }
            let base = lastWritten[generation] ?? edited.openedAt
            if SaveGuard.decide(openedAt: base, currentModification: current) == .conflict { return .conflict }
            let images = imageData(for: document, from: note.images)
            let html = try NotesHTMLWriter.write(document, images: images)
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
            await keepImages(of: document, images: images, noteID: id, generation: generation)
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
            if pending?.note.generation == open.generation { pending = nil }
        }
    }

    /// The bytes of every image block that has them; a missing one makes the writer throw.
    private func imageData(for document: NoteDocument, from files: [Int: URL]) -> [Int: NoteImageData] {
        var result: [Int: NoteImageData] = [:]
        for block in document.blocks {
            guard case .image(let index) = block, result[index] == nil, let url = files[index],
                  let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            result[index] = NoteImageData(data: data, mimeType: Self.mimeTypes[url.pathExtension.lowercased()] ?? "image/png")
        }
        return result
    }

    /// Notes gives written images new attachment ids: the cache keeps their bytes under those ids, so the note
    /// can be written again without Full Disk Access. The open document keeps its own indexes (an editor holding
    /// them stays right); only the files behind them move. Skipped when the ids do not line up.
    private func keepImages(of document: NoteDocument, images: [Int: NoteImageData], noteID: String, generation: Int) async {
        guard !images.isEmpty else { return }
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
        var moved: [Int: URL] = [:]
        for (slot, block) in slots {
            guard case .image(let index) = block, let image = images[index] else { continue }
            let ext = Self.mimeTypes.first(where: { $0.value == image.mimeType })?.key ?? "png"
            if let url = try? cache.store(image.data, forAttachmentID: ids[slot], fileExtension: ext) { moved[index] = url }
        }
        // A reload while the ids were read has its own indexes: these files must not be put behind them.
        guard var note = open, note.generation == generation else { return }
        for (index, url) in moved { note.images[index] = url }  // "new-" files left behind go with trim
        open = note
    }

    // MARK: Creating and deleting

    /// Makes a note in `folderID` (nil: the default folder, or the first one) and opens it. `document` re-creates a
    /// note's content, for instance after a conflict; its images come from the open note.
    func newNote(_ document: NoteDocument? = nil, in folderID: String? = nil) async {
        let imageFiles = open?.images ?? [:]  // the document's indexes are those of the load open now
        await flush()
        if folders.isEmpty { await refresh() }
        guard let folder = folders.first(where: { $0.id == folderID }) ?? folders.first(where: { $0.id == settings.defaultFolderID })
                ?? folders.first else {
            Self.log.error("No folder to make a note in")
            return
        }
        let document = document ?? NoteDocument(blocks: [.paragraph([])])
        do {
            let html = try NotesHTMLWriter.write(document, images: imageData(for: document, from: imageFiles))
            let id = try await service.create(in: folder.id, html: html)
            let generation = requestLoad()
            await refresh()
            await load(id, generation: generation)
        } catch {
            handle(error, "create")
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

    func delete(_ id: String) async {
        if pending?.note.id == id {
            debounceTask?.cancel()
            debounceTask = nil
            pending = nil
        }
        while let task = saveTask { await task.value }
        do {
            try await service.delete(id)
        } catch NotesServiceError.notFound {
            // Already gone: drop it here too.
        } catch {
            handle(error, "delete")
            return
        }
        forget(id)
        if open?.id == id {
            open = nil
            saveState = .saved
        }
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
