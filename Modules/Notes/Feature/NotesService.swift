import Foundation

/// Notes ids look like "x-coredata://UUID/ICNote/p96"; the number is the row key in its database.
public enum NotesIDs {
    public static func databaseKey(of id: String, entity: String) -> Int? {
        guard let range = id.range(of: "/\(entity)/p") else { return nil }
        return Int(id[range.upperBound...])
    }

    /// For "…/ICAttachment/pNN".
    public static func attachmentKey(of id: String) -> Int? { databaseKey(of: id, entity: "ICAttachment") }
}

/// A folder of Notes, with the account it lives in.
public struct NoteFolder: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var account: String
    public var noteCount: Int

    public init(id: String, name: String, account: String, noteCount: Int) {
        self.id = id
        self.name = name
        self.account = account
        self.noteCount = noteCount
    }
}

/// One line of the note list: no body, so listing stays cheap.
public struct NoteSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var folderID: String
    public var modified: Date
    public var snippet: String
    public var hasImages: Bool
    public var isLocked: Bool

    public init(id: String, name: String, folderID: String, modified: Date, snippet: String, hasImages: Bool, isLocked: Bool) {
        self.id = id
        self.name = name
        self.folderID = folderID
        self.modified = modified
        self.snippet = snippet
        self.hasImages = hasImages
        self.isLocked = isLocked
    }

    /// The NN of "…/ICNote/pNN": the note's row key in Notes' database.
    public var databaseKey: Int? { NotesIDs.databaseKey(of: id, entity: "ICNote") }
}

/// A note as AppleScript gives it: HTML body, plain text (images are U+FFFC), modification date.
public struct NoteContent: Sendable {
    public var html: String
    public var plainText: String
    public var modified: Date
    public var attachmentCount: Int

    public init(html: String, plainText: String, modified: Date, attachmentCount: Int) {
        self.html = html
        self.plainText = plainText
        self.modified = modified
        self.attachmentCount = attachmentCount
    }
}

/// `notRunning`: the Notes app is not open, so macOS cannot say yet. Only a service reports it; the store
/// starts Notes when it may (`NotesService.launch`) and asks again, and never keeps this value itself.
public enum NotesAccess: Equatable, Sendable { case unknown, granted, denied, notRunning }

public enum NotesServiceError: Error, Equatable {
    /// The user refused AraNotch control of Notes (Automation).
    case denied
    /// The note or folder does not exist (any more).
    case notFound
    case script(String)
}

/// Everything AraNotch does with Notes. `NotesBridge` is the real one; tests use a fake.
public protocol NotesService: Sendable {
    func access(askIfNeeded: Bool) async -> NotesAccess
    /// Starts Notes in the background, hidden, and returns once it is running (or after a few seconds).
    func launch() async
    func folders() async throws -> [NoteFolder]
    /// nil: every folder.
    func notes(in folderID: String?) async throws -> [NoteSummary]
    func content(of noteID: String) async throws -> NoteContent
    /// Ids ("…/ICAttachment/pNN") of the note's attachments, in order. Images are not read through
    /// AppleScript (`save attachment` fails); they come from the database's media files.
    func attachmentIDs(of noteID: String) async throws -> [String]
    /// Returns the new note's id.
    func create(in folderID: String, html: String) async throws -> String
    /// Returns the new modification date.
    func setBody(_ html: String, of noteID: String) async throws -> Date
    func modification(of noteID: String) async throws -> Date
    /// Moves the note to Recently Deleted.
    func delete(_ noteID: String) async throws
    func createFolder(named: String) async throws -> NoteFolder
    /// Opens the note in the Notes app.
    func show(_ noteID: String) async throws
}
