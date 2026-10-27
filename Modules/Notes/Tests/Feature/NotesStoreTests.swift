import Foundation
import Testing
import NotesCore
@testable import NotesFeature

/// A Notes database in memory: never the real NoteStore.sqlite.
private final class FakeDatabase: NoteDatabase, @unchecked Sendable {
    var readable = true
    var documents: [Int: NoteDocument] = [:]
    var files: [Int: URL] = [:]

    var isReadable: Bool { readable }
    func document(forNoteKey key: Int) -> (document: NoteDocument, attachments: [NoteStoreAttachment])? {
        documents[key].map { ($0, []) }
    }
    func attachmentFile(forAttachmentKey key: Int) -> URL? { files[key] }
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotesStoreTests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func p(_ text: String) -> NoteBlock { .paragraph([TextRun(text)]) }
private func imageCount(_ html: String?) -> Int { (html ?? "").components(separatedBy: "<img").count - 1 }
private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
private func attachmentID(_ n: Int) -> String { "x-coredata://FAKE/ICAttachment/p\(n)" }

@MainActor
private struct Harness {
    let fake = FakeNotesService()
    let cache = NoteImageCache(root: temporaryDirectory())
    let settings = NotesSettings(store: NotesSettingsStore(defaults: UserDefaults(suiteName: "notes.test.\(UUID().uuidString)")!))
    let folderID: String
    let store: NotesStore

    init(database: NoteDatabase? = nil, debounce: Duration = .milliseconds(10)) async throws {
        folderID = try await fake.createFolder(named: "Notes").id
        store = NotesStore(service: fake, database: database, cache: cache, settings: settings, debounce: debounce)
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
        h.store.edit(NoteDocument(blocks: [p("Title"), p("b")]))
        h.store.edit(NoteDocument(blocks: [p("Title"), p("bo")]))
        #expect(h.store.saveState == .pending)
        try await Task.sleep(for: .milliseconds(150))
        #expect(h.fake.setBodyCalls == 1)
        #expect(h.fake.lastHTML?.contains("bo") == true)
        #expect(h.store.saveState == .saved)
    }

    @Test func flushSavesImmediately() async throws {
        let h = try await Harness(debounce: .seconds(60))
        let id = h.plainNote()
        await h.store.openNote(id)
        h.store.edit(NoteDocument(blocks: [p("Title"), p("now")]))
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
        h.store.edit(NoteDocument(blocks: [p("a changed"), .image(attachmentIndex: 0), .image(attachmentIndex: 1)]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 1)
        #expect(imageCount(h.fake.lastHTML) == 2)
    }

    @Test func readOnlyWithoutDatabaseNeverWrites() async throws {
        let h = try await Harness()
        let id = h.fake.addNote("a", in: h.folderID, html: "<ul><li>a</li></ul>", plainText: "a")
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.listsUnknown]))
        h.store.edit(NoteDocument(blocks: [p("changed")]))
        await h.store.flush()
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func conflictDoesNotOverwrite() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        h.fake.touch(id, to: Date().addingTimeInterval(60))
        h.store.edit(NoteDocument(blocks: [p("Title"), p("mine")]))
        await h.store.flush()
        #expect(h.store.saveState == .conflict)
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func deletedElsewhereReportsDeleted() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        try await h.fake.delete(id)
        h.store.edit(NoteDocument(blocks: [p("Title"), p("mine")]))
        await h.store.flush()
        #expect(h.store.saveState == .deleted)
        #expect(h.fake.setBodyCalls == 0)
    }

    @Test func editDuringSaveSavesAgain() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        h.fake.setBodyDelay = .milliseconds(150)
        h.store.edit(NoteDocument(blocks: [p("Title"), p("first")]))
        try await Task.sleep(for: .milliseconds(60))
        #expect(h.store.saveState == .saving)
        h.store.edit(NoteDocument(blocks: [p("Title"), p("second")]))
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
        try await Task.sleep(for: .milliseconds(30))
        #expect(h.store.open?.id == a)  // B is still loading
        h.store.edit(NoteDocument(blocks: [p("A"), p("late keystroke")]))
        await opening.value
        #expect(h.store.open?.id == b)
        await h.store.flush()
        #expect(try await h.fake.content(of: b).html == "<div>B</div><div>body</div>")
        #expect(try await h.fake.content(of: a).html.contains("late keystroke"))
        #expect(h.fake.setBodyCalls == 1)
        #expect(h.store.saveState == .saved)
    }

    @Test func editMadeWhileTheSameNoteReloadsIsDropped() async throws {
        let h = try await Harness(debounce: .milliseconds(200))
        let a = h.plainNote("A")
        await h.store.openNote(a)
        h.fake.touch(a, to: Date().addingTimeInterval(60))  // changed in Notes meanwhile
        h.fake.contentDelay = .milliseconds(80)
        let reloading = Task { await h.store.reloadOpenNote() }
        try await Task.sleep(for: .milliseconds(30))
        h.store.edit(NoteDocument(blocks: [p("A"), p("stale")]))
        await reloading.value
        #expect(h.store.open?.safety == .editable)
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 0)
        #expect(h.store.saveState == .saved)
    }

    @Test func newImageIsEmbeddedOnSave() async throws {
        let h = try await Harness()
        let id = fakeOneImageNote(h)
        _ = try h.cache.store(pngBytes, forAttachmentID: attachmentID(1), fileExtension: "png")
        await h.store.openNote(id)
        let index = try #require(h.store.addImage(Data([9, 9, 9]), fileExtension: "jpg"))
        #expect(index == 1)
        h.store.edit(NoteDocument(blocks: [p("a"), .image(attachmentIndex: 0), .image(attachmentIndex: index)]))
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
        h.store.edit(NoteDocument(blocks: [p("a"), .image(attachmentIndex: added), .image(attachmentIndex: 0)]))
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

    @Test func missingImageBytesFailWithoutWriting() async throws {
        let h = try await Harness()
        let id = h.plainNote()
        await h.store.openNote(id)
        h.store.edit(NoteDocument(blocks: [p("Title"), .image(attachmentIndex: 5)]))
        await h.store.flush()
        #expect(h.fake.setBodyCalls == 0)
        guard case .failed = h.store.saveState else { Issue.record("expected failed, got \(h.store.saveState)"); return }
    }

    @Test func imagesUnavailableMakesReadOnly() async throws {
        let h = try await Harness()
        let id = fakeOneImageNote(h)
        await h.store.openNote(id)
        #expect(h.store.open?.safety == .readOnly([.imagesUnavailable]))
        h.store.edit(NoteDocument(blocks: [p("b"), .image(attachmentIndex: 0)]))
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
        h.store.edit(NoteDocument(blocks: [p("Title"), p("mine")]))
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

    @Test func newKeysRekey() throws {
        let cache = NoteImageCache(root: temporaryDirectory())
        let key = try cache.storeNew(pngBytes, fileExtension: "jpg")
        #expect(key.hasPrefix("new-"))
        #expect(cache.url(forKey: key) != nil)
        cache.rekey(key, to: attachmentID(3))
        #expect(cache.url(forKey: key) == nil)
        #expect(try Data(contentsOf: try #require(cache.url(forAttachmentID: attachmentID(3)))) == pngBytes)
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
