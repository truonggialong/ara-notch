import Foundation
import Testing
import NotesCore
@testable import NotesFeature

/// A Notes database in memory: never the real NoteStore.sqlite.
private final class FakeDatabase: NoteDatabase, @unchecked Sendable {
    var readable = true
    var documents: [Int: NoteDocument] = [:]
    /// Notes whose data has formatting the document cannot hold.
    var formatted: Set<Int> = []
    /// The row's modification date of a note (none: the database has no date).
    var modified: [Int: Date] = [:]
    /// The row keys of a note's attachments in document order; by default 1, 2… (`attachmentID(n)`).
    var attachmentKeys: [Int: [Int?]] = [:]
    var files: [Int: URL] = [:]
    /// Seconds an attachment lookup takes (it runs off the main actor).
    var fileDelay: TimeInterval = 0

    private let lock = NSLock()
    private var lookupCount = 0
    /// Attachment lookups begun, counted before `fileDelay`.
    var lookups: Int { lock.withLock { lookupCount } }

    var isReadable: Bool { readable }
    func note(forNoteKey key: Int) -> DatabaseNote? {
        documents[key].map {
            let count = NotesStore.attachmentBlocks($0).count
            return DatabaseNote(decoded: DecodedNote(document: $0, attachments: [], hasUnsupportedFormatting: formatted.contains(key)),
                                modified: modified[key], attachmentKeys: attachmentKeys[key] ?? (0..<count).map { $0 + 1 })
        }
    }
    func attachmentFile(forAttachmentKey key: Int) -> URL? {
        lock.withLock { lookupCount += 1 }
        if fileDelay > 0 { Thread.sleep(forTimeInterval: fileDelay) }
        return files[key]
    }
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotesStoreTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

extension NotesStore {
    /// An edit as the editor of the given load would send it.
    func edit(generation: Int?, _ document: NoteDocument) { edit(document, generation: generation ?? -1) }
}

/// Waits until `condition` holds, looking every 2 ms; records an issue after `timeout`. Used instead of sleeping for
/// a call to be under way, so a busy main actor cannot make a test miss its moment.
@MainActor
func waitUntil(_ what: String, timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now >= deadline {
            Issue.record("Timed out waiting until \(what)")
            return
        }
        try await Task.sleep(for: .milliseconds(2))
    }
}

private func p(_ text: String) -> NoteBlock { .paragraph([TextRun(text)]) }
private func imageCount(_ html: String?) -> Int { (html ?? "").components(separatedBy: "<img").count - 1 }
private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
private func attachmentID(_ n: Int) -> String { "x-coredata://FAKE/ICAttachment/p\(n)" }

@MainActor
private struct Harness {
    let fake = FakeNotesService()
    let cache: NoteImageCache
    let settings = NotesSettings(store: NotesSettingsStore(defaults: UserDefaults(suiteName: "notes.test.\(UUID().uuidString)")!))
    let folderID: String
    let store: NotesStore

    init(database: NoteDatabase? = nil, debounce: Duration = .milliseconds(10), imageDebounce: Duration? = nil,
         cacheLimit: Int = 200_000_000) async throws {
        cache = NoteImageCache(root: temporaryDirectory(), limitBytes: cacheLimit)
        folderID = try await fake.createFolder(named: "Notes").id
        store = NotesStore(service: fake, database: database, cache: cache, settings: settings, debounce: debounce,
                           imageDebounce: imageDebounce ?? debounce)
    }

    /// A two-paragraph note with no attachments.
    func plainNote(_ name: String = "Title") -> String {
        fake.addNote(name, in: folderID, html: "<div>\(name)</div><div>body</div>", plainText: "\(name)\nbody")
    }

    /// A note "a", image, image, whose image bytes are already in the cache.
    func twoImageNote() throws -> String {
        let id = fake.addNote("a", in: folderID, html: "<div>a</div><div><br></div><div><br></div>",
                              plainText: "a\n\u{FFFC}\n\u{FFFC}", attachments: [attachmentID(1), attachmentID(2)])
        _ = try cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        _ = try cache.store(pngBytes, forAttachmentID: attachmentID(2), fileExtension: "png")
        return id
    }
}

@MainActor @Suite struct NotesStoreTests {
    // MARK: Saving

    @Test func savesAfterTypingStops() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .editable)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("b")]))
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("bo")]))
        #expect(h.store.saveState == .pending)
        try await waitUntil("saved") { h.store.saveState == .saved }
        #expect(h.fake.setBodyCalls == 1)
        #expect(h.fake.lastHTML?.contains("bo") == true)
        #expect(h.store.saveState == .saved)
    }

    @Test func flushSavesImmediately() async throws {
        let h = try await Harness(debounce: .seconds(60))
        let id = h.plainNote()
        await h.store.openNote(id)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("now")]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 1)
        #expect(h.store.saveState == .saved)
    }

    @Test func keepsImagesWhenOnlyTextChanged() async throws {
        let h = try await Harness()
        let id = try h.twoImageNote()
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .editable)
        #expect(h.store.open?.images.count == 2)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("a changed"), .image(attachmentIndex: 0), .image(attachmentIndex: 1)]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 1)
        #expect(imageCount(h.fake.lastHTML) == 2)
    }

    @Test func readOnlyWithoutDatabaseNeverWrites() async throws {
        let h = try await Harness()
        let id = h.fake.addNote("a", in: h.folderID, html: "<ul><li>a</li></ul>", plainText: "a")
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.listsUnknown]))
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("changed")]))
        await h.store.flush()
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func conflictDoesNotOverwrite() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        h.fake.touch(id, to: Date().addingTimeInterval(60))
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("mine")]))
        await h.store.flush()
        #expect(h.store.saveState == .conflict)
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func deletedElsewhereReportsDeleted() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        try await h.fake.delete(id)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("mine")]))
        await h.store.flush()
        #expect(h.store.saveState == .deleted)
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func editDuringSaveSavesAgain() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        h.fake.setBodyDelay = .milliseconds(150)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("first")]))
        try await waitUntil("the save is writing") { h.fake.calls("setBody") == 1 }
        #expect(h.store.saveState == .saving)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("second")]))
        #expect(h.store.saveState == .pending)
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 2)
        #expect(h.fake.lastHTML?.contains("second") == true)
        #expect(h.store.saveState == .saved)
    }

    @Test func editForTheOldNoteIsNeverWrittenIntoTheNextOne() async throws {
        let h = try await Harness(debounce: .milliseconds(200))
        let a = h.plainNote("A")
        let b = h.plainNote("B")
        await h.store.openNote(a)
        h.fake.contentDelay = .milliseconds(80)
        let opening = Task { await h.store.openNote(b) }
        try await waitUntil("B is being read") { h.fake.calls("content:\(b)") == 1 }
        #expect(h.store.open?.id == a)  // B is still loading
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("A"), p("late keystroke")]))
        await opening.value
        #expect(h.store.open?.id == b)
        await h.store.flush()
        #expect(try await h.fake.content(of: b).html == "<div>B</div><div>body</div>")
        #expect(try await h.fake.content(of: a).html.contains("late keystroke"))
        #expect(h.fake.setBodyCalls == 1)
        #expect(h.store.saveState == .saved)
    }

    /// An edit that reaches the store during a reload and conflicts is not replaced by the reload: the note stays on
    /// that load with the conflict banner, so "Copy mine" still has it.
    @Test func editOnTheOldVersionDuringAReloadKeepsItAsAConflict() async throws {
        let h = try await Harness(debounce: .milliseconds(200))
        let a = h.plainNote("A")
        await h.store.openNote(a)
        let old = h.store.open?.generation
        h.fake.touch(a, to: Date().addingTimeInterval(60))  // changed in Notes meanwhile
        h.fake.contentDelay = .milliseconds(80)
        let reads = h.fake.calls("content:\(a)")
        let reloading = Task { await h.store.reloadOpenNote() }
        try await waitUntil("A is being read again") { h.fake.calls("content:\(a)") > reads }
        #expect(h.store.isReloading)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("A"), p("stale")]))
        await reloading.value
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 0)
        #expect(h.store.open?.generation == old)
        #expect(h.store.saveState == .conflict)
        #expect(h.store.open?.document.blocks.contains(p("stale")) == true)
        #expect(!h.store.isReloading)
    }

    /// Switching notes saves the one left first; when that save conflicts, the note stays open with the banner.
    @Test func switchingStaysOnANoteWhoseSaveConflicts() async throws {
        let h = try await Harness(debounce: .seconds(30))
        let a = h.plainNote("A")
        let b = h.plainNote("B")
        await h.store.openNote(a)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("A"), p("mine")]))
        h.fake.touch(a, to: Date().addingTimeInterval(60))
        await h.store.openNote(b)
        #expect(h.store.open?.id == a)
        #expect(h.store.saveState == .conflict)
        #expect(h.store.open?.document.blocks.contains(p("mine")) == true)
        // Once the conflict is seen, the user may leave the note.
        await h.store.openNote(b)
        #expect(h.store.open?.id == b)
    }

    /// An edit of the note being left that arrives while the next one loads, and conflicts, keeps that note open.
    @Test func lateConflictingEditOfTheNoteLeftKeepsItOpen() async throws {
        let h = try await Harness(debounce: .milliseconds(200))
        let a = h.plainNote("A")
        let b = h.plainNote("B")
        await h.store.openNote(a)
        h.fake.touch(a, to: Date().addingTimeInterval(60))
        h.fake.contentDelay = .milliseconds(80)
        let opening = Task { await h.store.openNote(b) }
        try await waitUntil("B is being read") { h.fake.calls("content:\(b)") == 1 }
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("A"), p("late")]))
        await h.store.flush()
        await opening.value
        #expect(h.store.open?.id == a)
        #expect(h.store.saveState == .conflict)
        #expect(h.store.open?.document.blocks.contains(p("late")) == true)
    }

    @Test func editDuringAReloadOfTheSameNoteIsKept() async throws {
        let h = try await Harness()
        let a = h.plainNote("A")
        await h.store.openNote(a)
        let old = h.store.open?.generation
        h.fake.contentDelay = .milliseconds(100)
        h.fake.setBodyDelay = .milliseconds(100)
        let reads = h.fake.calls("content:\(a)")
        let reopening = Task { await h.store.openNote(a) }
        try await waitUntil("A is being read again") { h.fake.calls("content:\(a)") > reads }
        h.store.edit(generation: old, NoteDocument(blocks: [p("A"), p("x")]))
        await reopening.value
        await h.store.flush()
        #expect(h.fake.lastHTML?.contains("x") == true)
        #expect(try await h.fake.content(of: a).html.contains("<div><span style=\"font-size: 18px; white-space: pre-wrap\">x</span></div>"))
        #expect(h.store.open?.document.blocks.contains(p("x")) == true)
        #expect(h.store.open?.generation != old)
        #expect(h.fake.setBodyCalls == 1)
    }

    @Test func reloadWhileImagesAreKeptGetsItsOwnImages() async throws {
        let h = try await Harness()
        let id = try h.twoImageNote()
        _ = try h.cache.store(Data([2, 2, 2]), forAttachmentID: attachmentID(2), fileExtension: "png")  // two different images
        await h.store.openNote(id)
        h.fake.setBodyDelay = .milliseconds(80)
        h.store.edit(generation: h.store.open?.generation,
                     NoteDocument(blocks: [p("a"), .image(attachmentIndex: 1), .image(attachmentIndex: 0)]))
        try await waitUntil("the save is writing") { h.fake.calls("setBody") == 1 }
        await h.store.reloadOpenNote()
        await h.store.flush()
        let open = try #require(h.store.open)
        let indexes = Set(open.document.blocks.compactMap { b -> Int? in if case .image(let i) = b { i } else { nil } })
        #expect(Set(open.images.keys) == indexes)
        // The k-th image shown has the bytes Notes now holds as its k-th image.
        let inNotes = try await h.fake.content(of: id).html.components(separatedBy: "base64,").dropFirst()
            .map { Data(base64Encoded: String($0.prefix { $0 != "\"" }))! }
        let shown = try open.document.blocks.compactMap { b -> Int? in if case .image(let i) = b { i } else { nil } }
            .map { try Data(contentsOf: try #require(open.images[$0])) }
        #expect(shown == Array(inNotes))
        #expect(inNotes.first == Data([2, 2, 2]))
    }

    @Test func editFromAnEarlierLoadIsIgnored() async throws {
        let h = try await Harness()
        let a = h.plainNote("A")
        let b = h.plainNote("B")
        await h.store.openNote(a)
        let old = h.store.open?.generation
        await h.store.openNote(b)
        h.store.edit(generation: old, NoteDocument(blocks: [p("A"), p("late")]))
        try await Task.sleep(for: .milliseconds(50))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 0)
        #expect(try await h.fake.content(of: b).html == "<div>B</div><div>body</div>")
        #expect(h.store.open?.document.blocks.contains(p("late")) == false)
    }

    @Test func twoEditsOfANoteLeftBehindBothReachNotes() async throws {
        let h = try await Harness()
        let a = h.plainNote("A")
        let b = h.plainNote("B")
        await h.store.openNote(a)
        let gen = h.store.open?.generation
        h.fake.setBodyDelay = .milliseconds(100)
        h.fake.setBodyDateOffset = 60  // each write moves the date far on
        h.fake.setContentDelay(.milliseconds(60), for: b)
        let opening = Task { await h.store.openNote(b) }
        try await waitUntil("B is being read") { h.fake.calls("content:\(b)") == 1 }
        h.store.edit(generation: gen, NoteDocument(blocks: [p("A"), p("one")]))
        try await waitUntil("A's save is writing") { h.fake.calls("setBody") == 1 }
        h.store.edit(generation: gen, NoteDocument(blocks: [p("A"), p("one two")]))
        await opening.value
        await h.store.flush()
        #expect(h.store.open?.id == b)
        #expect(h.fake.setBodyCalls == 2)
        #expect(try await h.fake.content(of: a).html.contains("one two"))
        #expect(h.store.saveState == .saved)
    }

    @Test func theLastNoteAskedForIsTheOneOpen() async throws {
        let h = try await Harness()
        let a = h.plainNote("A")
        let b = h.plainNote("B")
        h.fake.setContentDelay(.milliseconds(120), for: a)
        let first = Task { await h.store.openNote(a) }
        try await waitUntil("A is being read") { h.fake.calls("content:\(a)") == 1 }
        await h.store.openNote(b)
        await first.value
        #expect(h.store.open?.id == b)
    }

    /// A picture Notes got through HTML lies in a file with no extension: its bytes give its type.
    @Test func imageInAFileWithoutExtensionLoads() async throws {
        let dir = temporaryDirectory()
        let file = dir.appendingPathComponent("58E653A7-8BCF-426B-831B-82B3516D113B")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]).write(to: file)
        let db = FakeDatabase()
        db.files[1] = file
        let h = try await Harness(database: db)
        let a = h.fake.addNote("A", in: h.folderID, html: "<div>A</div><div><br></div>", plainText: "A\n\u{FFFC}",
                               attachments: [attachmentID(1)])
        db.documents[NotesIDs.databaseKey(of: a, entity: "ICNote")!] = NoteDocument(blocks: [p("A"), .image(attachmentIndex: 0)])
        await h.store.openNote(a)
        let open = try #require(h.store.open)
        #expect(open.safety == .editable)
        #expect(open.images[0]?.pathExtension == "png")
    }

    @Test func writeLandingWhileImagesLoadOpensAsConflict() async throws {
        let dir = temporaryDirectory()
        let file = dir.appendingPathComponent("photo.png")
        try pngBytes.write(to: file)
        let db = FakeDatabase()
        db.files[1] = file
        let h = try await Harness(database: db)
        let a = h.fake.addNote("A", in: h.folderID, html: "<div>A</div><div><br></div>", plainText: "A\n\u{FFFC}",
                               attachments: [attachmentID(1)])
        db.documents[NotesIDs.databaseKey(of: a, entity: "ICNote")!] = NoteDocument(blocks: [p("A"), .image(attachmentIndex: 0)])
        await h.store.openNote(a)
        let old = try #require(h.store.open?.generation)
        h.cache.remove(key: attachmentID(1))  // the reload has to wait for the database
        db.fileDelay = 0.15
        let lookups = db.lookups
        let reloading = Task { await h.store.reloadOpenNote() }
        try await waitUntil("the reload is loading images") { db.lookups > lookups }  // A's old editor still types
        h.store.edit(generation: old, NoteDocument(blocks: [p("A typed")]))  // its image file was removed above
        await reloading.value
        await h.store.flush()
        let reloaded = try #require(h.store.open)
        #expect(reloaded.generation != old)
        #expect(reloaded.safety == .editable)
        #expect(h.store.saveState == .conflict)
        let writes = h.fake.setBodyCalls
        #expect(writes == 1)  // the old editor's edit, within a second of the reload's read
        h.store.edit(generation: reloaded.generation, NoteDocument(blocks: [p("A"), .image(attachmentIndex: 0)]))
        try await Task.sleep(for: .milliseconds(40))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == writes)
        #expect(try await h.fake.content(of: a).html.contains("A typed"))
    }

    @Test func reloadWritesTheOldEditorsWaitingEditFirst() async throws {
        let dir = temporaryDirectory()
        let file = dir.appendingPathComponent("photo.png")
        try pngBytes.write(to: file)
        let db = FakeDatabase()
        db.files[1] = file
        let h = try await Harness(database: db, debounce: .seconds(10))  // the edit stays waiting
        let a = h.fake.addNote("A", in: h.folderID, html: "<div>A</div><div><br></div>", plainText: "A\n\u{FFFC}",
                               attachments: [attachmentID(1)])
        let key = NotesIDs.databaseKey(of: a, entity: "ICNote")!
        db.documents[key] = NoteDocument(blocks: [p("A"), .image(attachmentIndex: 0)])
        await h.store.openNote(a)
        let old = try #require(h.store.open?.generation)
        h.cache.remove(key: attachmentID(1))
        db.fileDelay = 0.15
        let lookups = db.lookups
        let reloading = Task { await h.store.reloadOpenNote() }
        try await waitUntil("the reload is loading images") { db.lookups > lookups }
        h.store.edit(generation: old, NoteDocument(blocks: [p("A & <typed>")]))
        await reloading.value
        #expect(h.store.saveState == .conflict)
        #expect(h.fake.setBodyCalls == 0)
        db.fileDelay = 0
        db.documents[key] = NoteDocument(blocks: [p("A & <typed>")])  // what Notes' database holds once written
        await h.store.reloadOpenNote()  // straight away, before the edit's debounce
        #expect(h.fake.setBodyCalls == 1)
        #expect(try await h.fake.content(of: a).html.contains("A &amp; &lt;typed&gt;"))
        #expect(h.store.open?.document.blocks == [p("A & <typed>")])
        #expect(h.store.open?.safety == .editable)
        #expect(h.store.saveState == .saved)
    }

    @Test func reloadThatNeverSettlesOpensAsConflict() async throws {
        let h = try await Harness(debounce: .milliseconds(1))
        let a = h.plainNote("A")
        await h.store.openNote(a)
        let old = try #require(h.store.open?.generation)
        h.fake.contentDelay = .milliseconds(60)
        h.fake.setBodyDelay = .milliseconds(3)
        // The old editor keeps typing all through the reload, each keystroke saved before the next one,
        // so a write lands during every read and the reads run out.
        let typing = Task { @MainActor in
            for i in 0..<40 {
                h.store.edit(generation: old, NoteDocument(blocks: [p("A"), p(String(repeating: "x", count: i + 1))]))
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        await h.store.reloadOpenNote()
        let reloaded = try #require(h.store.open)
        #expect(reloaded.generation != old)
        #expect(reloaded.safety == .editable)  // only the conflict holds its edits back
        await typing.value
        await h.store.flush()
        #expect(h.store.saveState == .conflict)
        let writes = h.fake.setBodyCalls
        h.store.edit(generation: reloaded.generation, NoteDocument(blocks: [p("A"), p("stale")]))
        try await Task.sleep(for: .milliseconds(40))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == writes)
        #expect(try await h.fake.content(of: a).html.contains("stale") == false)
    }

    @Test func imagesOfASaveUnderWayAreNotTrimmed() async throws {
        let h = try await Harness(cacheLimit: 1)  // every file not in use is trimmed
        let a = try h.twoImageNote()
        let b = h.fake.addNote("B", in: h.folderID, html: "<div>B</div><div><br></div>", plainText: "B\n\u{FFFC}",
                               attachments: [attachmentID(9)])
        await h.store.openNote(a)
        let genA = h.store.open?.generation
        h.fake.setContentDelay(.milliseconds(100), for: b)
        let opening = Task { await h.store.openNote(b) }
        try await waitUntil("B is being read") { h.fake.calls("content:\(b)") == 1 }
        h.fake.modificationDelay = .milliseconds(200)
        h.store.edit(generation: genA, NoteDocument(blocks: [p("a typed"), .image(attachmentIndex: 0), .image(attachmentIndex: 1)]))
        await opening.value
        #expect(h.store.open?.id == b)
        try await waitUntil("A's save is waiting on modification") { h.fake.calls("modification") == 1 }
        await h.store.reloadOpenNote()  // B's load trims the cache
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 1)
        #expect(imageCount(try await h.fake.content(of: a).html) == 2)
    }

    @Test func aWriteOfUnknownOutcomeIsNeverWrittenOver() async throws {
        let h = try await Harness()
        let a = h.plainNote("A")
        await h.store.openNote(a)
        h.fake.nextSetBodyFailsAfterWriting = true
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("A"), p("one")]))
        await h.store.flush()
        guard case .failed = h.store.saveState else { Issue.record("expected failed, got \(h.store.saveState)"); return }
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("A"), p("two")]))
        await h.store.flush()
        #expect(h.store.saveState == .conflict)
        #expect(h.fake.setBodyCalls == 1)
    }

    @Test func newImageIsEmbeddedOnSave() async throws {
        let h = try await Harness()
        let id = fakeOneImageNote(h)
        _ = try h.cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        await h.store.openNote(id)
        let index = try #require(h.store.addImage(Data([9, 9, 9]), fileExtension: "jpg"))
        #expect(index == 1)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("a"), .image(attachmentIndex: 0), .image(attachmentIndex: index)]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 1)
        #expect(imageCount(h.fake.lastHTML) == 2)
        #expect(h.fake.lastHTML?.contains("data:image/jpeg;base64,") == true)
    }

    @Test func savedImagesAreKeptUnderTheirNewIDs() async throws {
        let h = try await Harness()
        let id = fakeOneImageNote(h)
        _ = try h.cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        await h.store.openNote(id)
        let added = try #require(h.store.addImage(Data([9, 9, 9]), fileExtension: "png"))
        h.fake.setAttachments([attachmentID(7), attachmentID(8)], of: id)  // as Notes would after the write
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("a"), .image(attachmentIndex: added), .image(attachmentIndex: 0)]))
        await h.store.flush()
        #expect(h.store.saveState == .saved)
        let first = try #require(h.cache.url(forAttachmentID: attachmentID(7)))
        let second = try #require(h.cache.url(forAttachmentID: attachmentID(8)))
        #expect(try Data(contentsOf: first) == Data([9, 9, 9]))
        #expect(try Data(contentsOf: second) == pngBytes)
        // The open document keeps its own indexes, so an editor holding them still points at the right bytes.
        #expect(h.store.open?.document.blocks[1] == .image(attachmentIndex: added))
        #expect(try Data(contentsOf: try #require(h.store.open?.images[added])) == Data([9, 9, 9]))
    }

    /// The bytes are the same under the new id: the file is linked, not written again on every save.
    @Test func savedImagesAreLinkedNotRewritten() async throws {
        let h = try await Harness()
        let id = fakeOneImageNote(h)
        let old = try h.cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        await h.store.openNote(id)
        h.fake.setAttachments([attachmentID(7)], of: id)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("a changed"), .image(attachmentIndex: 0)]))
        await h.store.flush()
        let new = try #require(h.cache.url(forAttachmentID: attachmentID(7)))
        func inode(_ url: URL) throws -> Int? { try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int }
        #expect(try inode(new) == inode(old))
    }

    /// Every write of a note with pictures re-sends them to Notes and iCloud: it waits for a longer pause.
    @Test func aNoteWithImagesSavesAfterALongerPause() async throws {
        let h = try await Harness(debounce: .milliseconds(10), imageDebounce: .seconds(60))
        let id = fakeOneImageNote(h)
        _ = try h.cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        await h.store.openNote(id)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("a typed"), .image(attachmentIndex: 0)]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(h.fake.setBodyCalls == 0)
        #expect(h.store.saveState == .pending)
        await h.store.flush()   // leaving the page, closing the window or quitting
        #expect(h.fake.setBodyCalls == 1)
        let plain = h.plainNote("P")
        await h.store.openNote(plain)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("P"), p("typed")]))
        try await waitUntil("the plain note is saved") { h.fake.setBodyCalls == 2 }
    }

    @Test func missingImageBytesFailWithoutWriting() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), .image(attachmentIndex: 5)]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 0)
        guard case .failed = h.store.saveState else { Issue.record("expected failed, got \(h.store.saveState)"); return }
    }

    @Test func imagesUnavailableMakesReadOnly() async throws {
        let h = try await Harness()
        let id = fakeOneImageNote(h)
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.imagesUnavailable]))
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("b"), .image(attachmentIndex: 0)]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func imageComesFromTheDatabaseIntoTheCache() async throws {
        let dir = temporaryDirectory()
        let file = dir.appendingPathComponent("photo.jpeg")
        try pngBytes.write(to: file)
        let db = FakeDatabase()
        db.files[1] = file
        let h = try await Harness(database: db)
        let id = fakeOneImageNote(h)
        db.documents[NotesIDs.databaseKey(of: id, entity: "ICNote")!] = NoteDocument(blocks: [p("a"), .image(attachmentIndex: 0)])
        await h.store.openNote(id)
        #expect(h.store.fullView)
        #expect(h.store.open?.safety == .editable)
        #expect(h.cache.url(forAttachmentID: attachmentID(1)) != nil)
    }

    /// AppleScript may list a note's attachments in the order they were added; the database gives document order.
    /// An image pasted above an older one must still show (and be written back) in its own place.
    @Test func imagesFollowTheDatabasesDocumentOrder() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let id = try h.twoImageNote()
        _ = try h.cache.store(Data([2, 2, 2]), forAttachmentID: attachmentID(2), fileExtension: "png")
        let key = NotesIDs.databaseKey(of: id, entity: "ICNote")!
        db.documents[key] = NoteDocument(blocks: [p("a"), .image(attachmentIndex: 0), .image(attachmentIndex: 1)])
        db.attachmentKeys[key] = [2, 1]   // the second one added is the first in the note
        await h.store.openNote(id)
        let open = try #require(h.store.open)
        #expect(open.safety == .editable)
        #expect(try Data(contentsOf: try #require(open.images[0])) == Data([2, 2, 2]))
        #expect(try Data(contentsOf: try #require(open.images[1])) == pngBytes)
    }

    @Test func attachmentsTheDatabaseCannotPlaceMakeImagesUnavailable() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let id = try h.twoImageNote()
        let key = NotesIDs.databaseKey(of: id, entity: "ICNote")!
        db.documents[key] = NoteDocument(blocks: [p("a"), .image(attachmentIndex: 0), .image(attachmentIndex: 1)])
        db.attachmentKeys[key] = [1, 3]
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.imagesUnavailable]))
        db.attachmentKeys[key] = [1, nil]
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.imagesUnavailable]))
    }

    @Test func attachmentCountMismatchMakesImagesUnavailable() async throws {
        let h = try await Harness()
        let id = h.fake.addNote("a", in: h.folderID, html: "<div>a</div><div><br></div>", plainText: "a\n\u{FFFC}",
                                attachments: [attachmentID(1), attachmentID(2)])
        _ = try h.cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.imagesUnavailable]))
    }

    @Test func tableWithoutHTMLIsUnreadable() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let id = h.fake.addNote("a", in: h.folderID, html: "<div>a</div><div><br></div>", plainText: "a\n\u{FFFC}",
                                attachments: [attachmentID(1)])
        db.documents[NotesIDs.databaseKey(of: id, entity: "ICNote")!] = NoteDocument(blocks: [p("a"), .table(html: "", cells: [])])
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.unreadable]))
    }

    @Test func fullTableTakesItsHTMLFromAppleScript() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let table = "<object><table><tr><td>x</td></tr></table></object>"
        let id = h.fake.addNote("a", in: h.folderID, html: "<div>a</div>\(table)", plainText: "a\n\u{FFFC}",
                                attachments: [attachmentID(1)])
        db.documents[NotesIDs.databaseKey(of: id, entity: "ICNote")!] = NoteDocument(blocks: [p("a"), .table(html: "", cells: [])])
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .editable)
        guard case .table(let html, _)? = h.store.open?.document.blocks.last else { Issue.record("no table"); return }
        #expect(html == table)
    }

    @Test func formattingTheWriterCannotKeepMakesReadOnly() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let id = h.plainNote()
        let key = NotesIDs.databaseKey(of: id, entity: "ICNote")!
        db.documents[key] = NoteDocument(blocks: [p("Title"), p("body")])
        db.formatted = [key]
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.formatting]))
    }

    /// Notes writes its database a little after an edit: data whose row date is not the note's date may lack that
    /// edit (a line just made a checklist), so the note is not written from it.
    @Test func databaseRowOlderThanTheNoteIsUnreadable() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let id = h.fake.addNote("a", in: h.folderID, html: "<div>a</div>", plainText: "a", modified: date)
        let key = NotesIDs.databaseKey(of: id, entity: "ICNote")!
        db.documents[key] = NoteDocument(blocks: [p("a")])
        db.modified[key] = date.addingTimeInterval(-5)
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.unreadable]))
        db.modified[key] = date.addingTimeInterval(0.4)   // the same second, as AppleScript gives it
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .editable)
    }

    @Test func fullDocumentIsShownWhenReadable() async throws {
        let db = FakeDatabase()
        let h = try await Harness(database: db)
        let id = h.fake.addNote("a", in: h.folderID, html: "<ul><li>a</li></ul>", plainText: "a")
        db.documents[NotesIDs.databaseKey(of: id, entity: "ICNote")!] = NoteDocument(blocks: [.listItem(.dash, indent: 0, [TextRun("a")])])
        await h.store.openNote(id)
        #expect(h.store.open?.document.blocks == [.listItem(.dash, indent: 0, [TextRun("a")])])
        #expect(h.store.open?.safety == .editable)
    }

    @Test func lockedNoteIsReadOnly() async throws {
        let h = try await Harness()
        let id = h.fake.addNote("a", in: h.folderID, html: "", plainText: "", locked: true)
        await h.store.refresh()
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.locked]))
    }

    /// Locked in Notes after the listing: the note opens read only, not as an empty editable note.
    @Test func noteLockedSinceTheListingIsReadOnly() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.refresh()
        h.fake.lock(id)
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.locked]))
    }

    @Test func lockedNoteOutsideTheListIsStillFound() async throws {
        let h = try await Harness()
        let id = h.fake.addNote("a", in: h.folderID, html: "", plainText: "", locked: true)
        await h.store.openNote(id)  // no refresh first
        #expect(h.store.open?.safety == .readOnly([.locked]))
    }

    // MARK: Lists, search, settings

    @Test func searchIgnoresDiacritics() async throws {
        let h = try await Harness()
        h.fake.addNote("Việc nhà", in: h.folderID, html: "", plainText: "")
        h.fake.addNote("Đi chợ", in: h.folderID, html: "", plainText: "")
        h.fake.addNote("Other", in: h.folderID, html: "", plainText: "", snippet: "rau củ")
        await h.store.refresh()
        h.store.searchText = "viec"
        #expect(h.store.visibleNotes.map(\.name) == ["Việc nhà"])
        h.store.searchText = "di cho"
        #expect(h.store.visibleNotes.map(\.name) == ["Đi chợ"])
        h.store.searchText = "RAU CU"
        #expect(h.store.visibleNotes.map(\.name) == ["Other"])
        h.store.searchText = ""
        #expect(h.store.visibleNotes.count == 3)
    }

    @Test func newNoteGoesToDefaultFolder() async throws {
        let h = try await Harness()
        let second = try await h.fake.createFolder(named: "Second")
        h.settings.defaultFolderID = second.id
        await h.store.refresh()
        await h.store.newNote()
        let created = try await h.fake.notes(in: second.id)
        #expect(created.count == 1)
        #expect(h.store.open?.id == created.first?.id)
        #expect(h.store.open?.safety == .editable)
    }

    /// Right after login Notes may be closed and nothing listed yet: a new note starts it rather than doing nothing.
    @Test func newNoteStartsAClosedNotes() async throws {
        let h = try await Harness()
        h.fake.accessValue = .notRunning
        h.fake.accessAfterLaunch = .granted
        await h.store.newNote()
        #expect(h.fake.launchCalls == 1)
        #expect(h.store.open != nil)
    }

    @Test func newNoteFallsBackToFirstFolder() async throws {
        let h = try await Harness()
        h.settings.defaultFolderID = "x-coredata://FAKE/ICFolder/p999"
        await h.store.newNote(NoteDocument(blocks: [p("again")]))
        let created = try await h.fake.notes(in: h.folderID)
        #expect(created.count == 1)
        #expect(try await h.fake.content(of: created[0].id).html.contains("again"))
    }

    @Test func recentIDsCapAtTwenty() async throws {
        let h = try await Harness()
        let ids = (0..<25).map { h.plainNote("N\($0)") }
        for id in ids { await h.store.openNote(id) }
        #expect(h.settings.recentIDs.count == 20)
        #expect(h.settings.recentIDs.first == ids.last)
        await h.store.openNote(ids[20])
        #expect(h.settings.recentIDs.first == ids[20])
        #expect(h.settings.recentIDs.count == 20)
    }

    @Test func deniedAccessDoesNotList() async throws {
        let h = try await Harness()
        h.plainNote()
        h.fake.accessValue = .denied
        await h.store.refresh()
        #expect(h.store.access == .denied)
        #expect(h.store.folders.isEmpty)
        #expect(h.store.notes.isEmpty)
    }

    @Test func deleteClearsOpenNoteAndRecents() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.refresh()
        await h.store.openNote(id)
        await h.store.delete(id)
        #expect(h.store.open == nil)
        #expect(h.store.notes.isEmpty)
        #expect(!h.settings.recentIDs.contains(id))
    }

    @Test func reloadAfterConflictShowsTheirVersion() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        _ = try await h.fake.setBody("<div>Title</div><div>theirs</div>", of: id)
        h.fake.touch(id, to: Date().addingTimeInterval(60))
        h.store.edit(generation: h.store.open?.generation, NoteDocument(blocks: [p("Title"), p("mine")]))
        await h.store.flush()
        #expect(h.store.saveState == .conflict)
        await h.store.reloadOpenNote()
        #expect(h.store.saveState == .saved)
        #expect(h.store.open?.document.blocks.last == p("theirs"))
        #expect(h.fake.setBodyCalls == 1)  // only the write made by the test itself
    }

    @Test func settingsStoreRoundTrips() {
        let store = NotesSettingsStore(defaults: UserDefaults(suiteName: "notes.test.\(UUID().uuidString)")!)
        #expect(store.recentIDs.isEmpty)
        #expect(store.selectedFolderID == nil)
        store.recentIDs = ["a", "b"]
        store.selectedFolderID = "f"
        store.defaultFolderID = "d"
        #expect(store.recentIDs == ["a", "b"])
        #expect(store.selectedFolderID == "f")
        #expect(store.defaultFolderID == "d")
        store.selectedFolderID = nil
        #expect(store.selectedFolderID == nil)
    }

    private func fakeOneImageNote(_ h: Harness) -> String {
        h.fake.addNote("a", in: h.folderID, html: "<div>a</div><div><br></div>", plainText: "a\n\u{FFFC}",
                       attachments: [attachmentID(1)])
    }

    // MARK: Access when Notes is closed

    @Test func closedNotesIsStartedWhenThePageAppears() async throws {
        let h = try await Harness()
        _ = h.plainNote()
        h.fake.accessValue = .notRunning
        h.fake.accessAfterLaunch = .granted
        await h.store.refresh(launchingNotes: true)
        #expect(h.fake.launchCalls == 1)
        #expect(h.store.access == .granted)
        #expect(h.store.notes.count == 1)
        #expect(!h.fake.accessChecks.contains(true))  // a passive check never asks
    }

    @Test func closedNotesKeepsAKnownGrant() async throws {
        let h = try await Harness()
        _ = h.plainNote()
        await h.store.refresh()
        #expect(h.store.access == .granted)
        h.fake.accessValue = .notRunning
        await h.store.refresh()
        #expect(h.store.access == .granted)
        #expect(h.store.notes.count == 1)
        #expect(h.fake.launchCalls == 0)
    }

    @Test func closedNotesWithoutLaunchingIsUnknown() async throws {
        let h = try await Harness()
        h.fake.accessValue = .notRunning
        await h.store.refresh()
        #expect(h.store.access == .unknown)
        #expect(h.fake.launchCalls == 0)
    }

    @Test func allowStartsNotesThenAsks() async throws {
        let h = try await Harness()
        h.fake.accessValue = .notRunning
        h.fake.accessAfterLaunch = .granted
        await h.store.requestAccess()
        #expect(h.fake.launchCalls == 1)
        #expect(Array(h.fake.accessChecks.prefix(2)) == [true, true])
        #expect(h.store.access == .granted)
    }

    @Test func notesThatStaysClosedAfterAllowIsNotGranted() async throws {
        let h = try await Harness()
        h.fake.accessValue = .notRunning
        await h.store.requestAccess()
        #expect(h.fake.launchCalls == 1)
        #expect(h.store.access == .unknown)
    }
}

@Suite struct NoteImageCacheTests {
    @Test func storesAndFindsByAttachmentID() throws {
        let cache = NoteImageCache(root: temporaryDirectory())
        #expect(cache.url(forAttachmentID: attachmentID(1)) == nil)
        let url = try cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "PNG")
        #expect(cache.url(forAttachmentID: attachmentID(1)) == url)
        #expect(url.pathExtension == "png")
        #expect(!url.lastPathComponent.contains(":"))
    }

    @Test func newKeysAreFound() throws {
        let cache = NoteImageCache(root: temporaryDirectory())
        let key = try cache.storeNew(pngBytes, fileExtension: "jpg")
        #expect(key.hasPrefix("new-"))
        #expect(try Data(contentsOf: try #require(cache.url(forKey: key))) == pngBytes)
    }

    @Test func trimKeepsFilesInUse() throws {
        let cache = NoteImageCache(root: temporaryDirectory(), limitBytes: 5)
        let used = try cache.store(Data(count: 10), forAttachmentID: attachmentID(1), fileExtension: "png")
        _ = try cache.store(Data(count: 10), forAttachmentID: attachmentID(2), fileExtension: "png")
        cache.trim(keeping: [used])
        #expect(cache.url(forAttachmentID: attachmentID(1)) != nil)
        #expect(cache.url(forAttachmentID: attachmentID(2)) == nil)
    }

    @Test func trimRemovesOldestFirst() throws {
        let cache = NoteImageCache(root: temporaryDirectory(), limitBytes: 25)
        let old = try cache.store(Data(count: 10), forAttachmentID: attachmentID(1), fileExtension: "png")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100)], ofItemAtPath: old.path)
        _ = try cache.store(Data(count: 10), forAttachmentID: attachmentID(2), fileExtension: "png")
        _ = try cache.store(Data(count: 10), forAttachmentID: attachmentID(3), fileExtension: "png")
        cache.trim()
        #expect(cache.url(forAttachmentID: attachmentID(1)) == nil)
        #expect(cache.url(forAttachmentID: attachmentID(2)) != nil)
        #expect(cache.url(forAttachmentID: attachmentID(3)) != nil)
    }
}
