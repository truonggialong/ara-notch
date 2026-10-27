import Foundation
import Testing
@testable import NotesCore

@Suite struct NoteImageFormatTests {
    @Test func tellsPicturesByTheirFirstBytes() {
        #expect(NoteImageFormat.fileExtension(of: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0])) == "png")
        #expect(NoteImageFormat.fileExtension(of: Data([0xFF, 0xD8, 0xFF, 0xE0])) == "jpeg")
        #expect(NoteImageFormat.fileExtension(of: Data("GIF89a".utf8)) == "gif")
        #expect(NoteImageFormat.fileExtension(of: Data([0x4D, 0x4D, 0x00, 0x2A, 0])) == "tiff")
        #expect(NoteImageFormat.fileExtension(of: Data([0, 0, 0, 0x18]) + Data("ftypheic".utf8)) == "heic")
        #expect(NoteImageFormat.fileExtension(of: Data("%PDF-1.7".utf8)) == nil)
        #expect(NoteImageFormat.fileExtension(of: Data([0x89, 0x50])) == nil)
        #expect(NoteImageFormat.fileExtension(of: Data()) == nil)
    }

    @Test func showsOnlyTheNamedFilesAsImages() {
        let note = DecodedNote(document: NoteDocument(blocks: [
            .file(attachmentIndex: 0, name: "", uti: "public.data"), .paragraph([TextRun("x")]),
            .file(attachmentIndex: 1, name: "", uti: "public.data"),
        ]), attachments: [])
        #expect(note.showingAsImages([1]).document.blocks == [
            .file(attachmentIndex: 0, name: "", uti: "public.data"), .paragraph([TextRun("x")]), .image(attachmentIndex: 1),
        ])
        #expect(note.showingAsImages([]) == note)
    }
}
