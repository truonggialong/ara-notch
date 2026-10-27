import Foundation
import Testing
@testable import NotesFeature

@Suite struct NotesScriptsTests {
    @Test func escapesQuotesInNames() {
        let script = NotesScripts.createFolder(named: "A \"b\" \\")
        #expect(script.contains("\"A \\\"b\\\" \\\\\""))
    }

    @Test func setBodyReadsHTMLFromFile() {
        let script = NotesScripts.setBody(noteID: "x-coredata://AA/ICNote/p1", htmlPath: "/tmp/x.html")
        #expect(script.contains("read POSIX file \"/tmp/x.html\" as «class utf8»"))
        #expect(script.contains("set body of"))
        #expect(script.contains("note id \"x-coredata://AA/ICNote/p1\""))
    }

    @Test func createUsesFolderIDAndFile() {
        let script = NotesScripts.create(folderID: "F\"1", htmlPath: "/tmp/y.html")
        #expect(script.contains("make new note at folder id \"F\\\"1\" with properties {body:h}"))
    }

    @Test func databaseKeyFromID() {
        let note = NoteSummary(id: "x-coredata://AA/ICNote/p96", name: "n", folderID: "f", modified: Date(),
                               snippet: "", hasImages: false, isLocked: false)
        #expect(note.databaseKey == 96)
        let other = NoteSummary(id: "x-coredata://AA/ICFolder/p3", name: "n", folderID: "f", modified: Date(),
                                snippet: "", hasImages: false, isLocked: false)
        #expect(other.databaseKey == nil)
    }

    @Test func listingFetchesPropertiesAsLists() {
        let all = NotesScripts.listNotes(folderID: nil)
        #expect(all.contains("id of notes"))
        #expect(all.contains("modification date of notes"))
        #expect(all.contains("password protected of notes"))
        let one = NotesScripts.listNotes(folderID: "f1")
        #expect(one.contains("of notes of folder id \"f1\""))
    }

    /// The lock state comes with the content, read at open time, not from the last listing.
    @Test func contentReadsTheLockState() {
        #expect(NotesScripts.content(noteID: "n1").contains("password protected of n}"))
    }

    @Test func attachmentIDsListsInOrder() {
        #expect(NotesScripts.attachmentIDs(noteID: "n1").contains("id of attachments of note id \"n1\""))
    }

    @Test func attachmentKeyFromID() {
        #expect(NotesIDs.attachmentKey(of: "x-coredata://AA/ICAttachment/p12") == 12)
        #expect(NotesIDs.attachmentKey(of: "x-coredata://AA/ICNote/p12") == nil)
    }

    @Test func listingDereferencesIDsAndSkipsRecentlyDeleted() {
        let all = NotesScripts.listNotes(folderID: nil)
        #expect(all.contains("set fid to contents of fref"))
        #expect(all.contains("\"Recently Deleted\""))
        #expect(all.contains("\"Đã xoá gần đây\"") && all.contains("\"Đã xóa gần đây\""))
        #expect(NotesScripts.snippets(noteIDs: ["a"]).contains("contents of iref"))
    }

    @Test func showActivatesNotes() {
        let script = NotesScripts.show(noteID: "n1")
        #expect(script.contains("show note id \"n1\""))
        #expect(script.contains("activate"))
    }

    @Test func fakeServiceBasics() async throws {
        let fake = FakeNotesService()
        let folder = try await fake.createFolder(named: "F")
        let id = try await fake.create(in: folder.id, html: "<div>a</div>")
        let before = try await fake.modification(of: id)
        fake.touch(id, to: before.addingTimeInterval(60))
        #expect(try await fake.modification(of: id) == before.addingTimeInterval(60))
        _ = try await fake.setBody("<div>b</div>", of: id)
        #expect(fake.setBodyCalls == 1)
        #expect(fake.lastHTML == "<div>b</div>")
        #expect(try await fake.content(of: id).html == "<div>b</div>")
        fake.setAttachments(["x-coredata://FAKE/ICAttachment/p1"], of: id)
        #expect(try await fake.attachmentIDs(of: id).count == 1)
        try await fake.delete(id)
        await #expect(throws: NotesServiceError.notFound) { try await fake.content(of: "nope") }
        await #expect(throws: NotesServiceError.notFound) { try await fake.content(of: id) }
    }
}
