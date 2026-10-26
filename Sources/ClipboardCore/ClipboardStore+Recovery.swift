import Foundation

public extension ClipboardStore {
    /// A history opened for use, and where a damaged one was put aside, if it had to be.
    struct Opened {
        public let store: ClipboardStore
        /// The damaged file, kept as it was; nil when the history opened as it is.
        public let setAside: URL?
    }

    /// Opens the history in `directory`. A damaged history (a crash in the middle of a write,
    /// a failing disk) would otherwise leave the clipboard unable to keep anything: it is moved
    /// aside, kept as it was for whoever wants to rescue it, and a fresh history takes its place.
    /// A history written by a newer version of the app is not damaged and is left alone.
    /// - Parameter date: when this happens, for the name the damaged file is kept under.
    static func openRecovering(directory: URL, maxItems: Int, at date: Date = Date()) throws -> Opened {
        do {
            let store = try ClipboardStore(directory: directory, maxItems: maxItems)
            try store.checkIntegrity()
            return Opened(store: store, setAside: nil)
        } catch let error where isDamage(error) {
            // The failed store is gone by now, and its file closed with it.
            let aside = try setAside(in: directory, at: date)
            return Opened(store: try ClipboardStore(directory: directory, maxItems: maxItems), setAside: aside)
        }
    }

    /// Reads the whole file through once, so damage anywhere in it is found now rather than on
    /// some later copy.
    func checkIntegrity() throws {
        let rows = try database.query("PRAGMA quick_check")
        let findings = rows.compactMap { $0.first?.string }
        guard findings == ["ok"] else {
            throw ClipboardStoreError.damaged(findings.prefix(3).joined(separator: "; "))
        }
    }

    private static func isDamage(_ error: Error) -> Bool {
        switch error as? ClipboardStoreError {
        case .damaged:
            return true
        case .sqlite(let message), .cannotOpen(let message):
            let text = message.lowercased()
            return text.contains("malformed") || text.contains("not a database") || text.contains("corrupt")
        default:
            return false
        }
    }

    /// Moves the history file, and the journal files SQLite may have beside it, out of the way
    /// under `clipboard-damaged-<date>.sqlite`. Returns where the history file went.
    private static func setAside(in directory: URL, at date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)
        let manager = FileManager.default
        var name = "clipboard-damaged-\(stamp)"
        var number = 2
        while manager.fileExists(atPath: directory.appendingPathComponent(name + ".sqlite").path) {
            name = "clipboard-damaged-\(stamp)-\(number)"
            number += 1
        }
        let destination = directory.appendingPathComponent(name + ".sqlite")
        do {
            try manager.moveItem(at: directory.appendingPathComponent("clipboard.sqlite"), to: destination)
        } catch {
            throw ClipboardStoreError.cannotOpen(error.localizedDescription)
        }
        for suffix in ["-wal", "-shm", "-journal"] {
            let journal = directory.appendingPathComponent("clipboard.sqlite" + suffix)
            if manager.fileExists(atPath: journal.path) {
                try? manager.moveItem(at: journal, to: directory.appendingPathComponent(name + ".sqlite" + suffix))
            }
        }
        return destination
    }
}
