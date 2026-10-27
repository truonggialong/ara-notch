import Foundation

/// AppleScript source for each Notes command. Pure strings, so they can be tested without Notes.
/// Every interpolated string goes through `quoted`; HTML never goes in the source, only a file path.
enum NotesScripts {
    /// Names of the "Recently Deleted" folder in the languages we know. Notes marks it by no property,
    /// only by name, and it must not show in the folder list or in "all notes".
    static let trashFolderNames = ["Recently Deleted", "Đã xoá gần đây", "Đã xóa gần đây"]

    /// A string literal, with backslash and quote escaped.
    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// {{id, name, account, note count}, …}
    static func listFolders() -> String {
        """
        tell application "Notes"
            set out to {}
            repeat with a in every account
                set an to name of a
                repeat with f in every folder of a
                    set end of out to {id of f, name of f, an, count of notes of f}
                end repeat
            end repeat
            return out
        end tell
        """
    }

    /// {{folder id, ids, names, modification dates, password protected flags}, …}, one entry per folder.
    /// Each property is fetched as a list for the whole folder, not note by note. The folder id is
    /// gathered per folder because `container of every note` is not reliable as one list.
    static func listNotes(folderID: String?) -> String {
        func entry(_ folder: String) -> String {
            "set end of out to {\(folder), id of notes of folder id \(folder), name of notes of folder id \(folder), "
                + "modification date of notes of folder id \(folder), password protected of notes of folder id \(folder)}"
        }
        if let folderID {
            return """
            tell application "Notes"
                set out to {}
                \(entry(quoted(folderID)))
                return out
            end tell
            """
        }
        let skipped = trashFolderNames.map(quoted).joined(separator: ", ")
        return """
        tell application "Notes"
            set out to {}
            set fids to id of every folder
            repeat with fref in fids
                set fid to contents of fref
                if (name of folder id fid) is not in {\(skipped)} then
                    \(entry("fid"))
                end if
            end repeat
            return out
        end tell
        """
    }

    /// {{plain text (cut to 400 characters), attachment count}, …} in the order of `noteIDs`.
    /// A locked note gives {"", 0}.
    static func snippets(noteIDs: [String]) -> String {
        let list = noteIDs.map(quoted).joined(separator: ", ")
        return """
        tell application "Notes"
            set out to {}
            repeat with iref in {\(list)}
                try
                    set nid to contents of iref
                    set n to note id nid
                    set p to plaintext of n
                    if (length of p) > 400 then set p to text 1 thru 400 of p
                    set end of out to {p, count of attachments of n}
                on error
                    set end of out to {"", 0}
                end try
            end repeat
            return out
        end tell
        """
    }

    /// {body, plaintext, modification date, attachment count, password protected}
    static func content(noteID: String) -> String {
        """
        tell application "Notes"
            set n to note id \(quoted(noteID))
            return {body of n, plaintext of n, modification date of n, count of attachments of n, password protected of n}
        end tell
        """
    }

    /// Ids of the note's attachments, in order.
    static func attachmentIDs(noteID: String) -> String {
        """
        tell application "Notes" to return id of attachments of note id \(quoted(noteID))
        """
    }

    /// Returns the new note's id.
    static func create(folderID: String, htmlPath: String) -> String {
        """
        set h to read POSIX file \(quoted(htmlPath)) as «class utf8»
        tell application "Notes"
            set n to make new note at folder id \(quoted(folderID)) with properties {body:h}
            return id of n
        end tell
        """
    }

    /// Returns the new modification date.
    static func setBody(noteID: String, htmlPath: String) -> String {
        """
        set h to read POSIX file \(quoted(htmlPath)) as «class utf8»
        tell application "Notes"
            set n to note id \(quoted(noteID))
            set body of n to h
            return modification date of n
        end tell
        """
    }

    static func modification(noteID: String) -> String {
        """
        tell application "Notes" to return modification date of note id \(quoted(noteID))
        """
    }

    static func delete(noteID: String) -> String {
        """
        tell application "Notes" to delete note id \(quoted(noteID))
        """
    }

    /// {id, name, account name}
    static func createFolder(named name: String) -> String {
        """
        tell application "Notes"
            set f to make new folder with properties {name:\(quoted(name))}
            set an to ""
            try
                set an to name of container of f
            end try
            return {id of f, name of f, an}
        end tell
        """
    }

    static func show(noteID: String) -> String {
        """
        tell application "Notes"
            show note id \(quoted(noteID))
            activate
        end tell
        """
    }
}
