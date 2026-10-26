import Foundation
import SQLite3

enum SQLiteValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    var int64: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var double: Double? {
        switch self {
        case .real(let value): return value
        case .integer(let value): return Double(value)
        default: return nil
        }
    }

    var string: String? {
        if case .text(let value) = self { return value }
        return nil
    }
}

/// Minimal wrapper around one SQLite connection. Values are always bound, never interpolated.
final class SQLiteDatabase {
    /// Tells SQLite to copy bound strings, because Swift frees them after the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private var handle: OpaquePointer?

    /// - Parameter readOnly: open an existing file without the right to change it.
    init(path: String, readOnly: Bool = false) throws {
        let access = readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(path, &handle, access | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(handle)
            throw ClipboardStoreError.cannotOpen(message)
        }
        // Another process may hold the file for a moment (the app writing, a helper reading).
        sqlite3_busy_timeout(handle, 2000)
    }

    deinit {
        sqlite3_close(handle)
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    var userVersion: Int {
        get throws {
            Int(try query("PRAGMA user_version").first?.first?.int64 ?? 0)
        }
    }

    func setUserVersion(_ version: Int) throws {
        // PRAGMA takes no bound parameters; the value is an Int, so this cannot inject.
        try execute("PRAGMA user_version = \(version)")
    }

    func execute(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        _ = try query(sql, bindings)
    }

    func query(_ sql: String, _ bindings: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(statement, index)
            case .integer(let number): result = sqlite3_bind_int64(statement, index, number)
            case .real(let number): result = sqlite3_bind_double(statement, index, number)
            case .text(let string): result = sqlite3_bind_text(statement, index, string, -1, Self.transient)
            }
            guard result == SQLITE_OK else { throw lastError() }
        }

        var rows: [[SQLiteValue]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column(statement, $0) })
            case SQLITE_DONE:
                return rows
            default:
                throw lastError()
            }
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            return sqlite3_column_text(statement, index).map { .text(String(cString: $0)) } ?? .null
        default:
            return .null
        }
    }

    private func lastError() -> ClipboardStoreError {
        .sqlite(String(cString: sqlite3_errmsg(handle)))
    }
}
