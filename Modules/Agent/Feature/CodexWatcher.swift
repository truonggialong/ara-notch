import AgentCore
import CoreServices
import Foundation

/// Follows Codex by reading the session logs it writes itself (`~/.codex/sessions`). Nothing
/// of Codex is changed. Only lines that say how a session is doing are decoded; lines that
/// hold conversation content are skipped unread.
@MainActor
final class CodexWatcher {
    /// Logs not touched for this long are not opened at all.
    private static let recentWindow: TimeInterval = 12 * 3600

    /// Session events, with the Codex session id they belong to.
    var onEvents: (([(sessionID: String, event: CodexRolloutEvent)]) -> Void)?

    let directory: URL
    private var stream: FSEventStreamRef?
    /// How far each log was read, and the session it belongs to once that is known.
    private var files: [String: (offset: UInt64, remainder: Data, sessionID: String?)] = [:]

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    var isRunning: Bool { stream != nil }

    /// Reads the recent logs, then is told by the system whenever one changes: no polling.
    func start() {
        guard stream == nil, FileManager.default.fileExists(atPath: directory.path) else { return }
        scanRecent()

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<CodexWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            // The stream is scheduled on the main queue.
            MainActor.assumeIsolated { watcher.read(paths: Array(changed.prefix(count))) }
        }
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags)
        else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        files = [:]
    }

    private func scanRecent() {
        let cutoff = Date().addingTimeInterval(-Self.recentWindow)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return }
        var recent: [(path: String, modified: Date)] = []
        var newest: (path: String, modified: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate
            else { continue }
            if modified > (newest?.modified ?? .distantPast) {
                newest = (url.path, modified)
            }
            if modified >= cutoff {
                recent.append((url.path, modified))
            }
        }
        // With nothing recent, the newest log is still read: its rate limits are the last
        // known ones, and a weekly window outlives a quiet day. Its session is too old to be
        // listed and drops out by itself.
        if recent.isEmpty, let newest {
            recent = [newest]
        }
        // Oldest first, so the newest log's rate limits are the ones left standing.
        read(paths: recent.sorted { $0.modified < $1.modified }.map(\.path))
    }

    private func read(paths: [String]) {
        var events: [(sessionID: String, event: CodexRolloutEvent)] = []
        for path in paths where path.hasSuffix(".jsonl") {
            events += readNew(in: path)
        }
        if !events.isEmpty {
            onEvents?(events)
        }
    }

    /// Reads what was appended to a log since the last time.
    private func readNew(in path: String) -> [(sessionID: String, event: CodexRolloutEvent)] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        var state = files[path] ?? (0, Data(), nil)
        let size = (try? handle.seekToEnd()) ?? 0
        if size < state.offset {
            state = (0, Data(), nil)
        }
        guard size > state.offset, (try? handle.seek(toOffset: state.offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else {
            files[path] = state
            return []
        }
        state.offset += UInt64(data.count)
        state.remainder.append(data)

        var events: [(sessionID: String, event: CodexRolloutEvent)] = []
        // The lines are walked through in place and only what is left after the last one is
        // kept: cutting each line off the front of a log of many megabytes copied the rest of
        // it every time. Lines that cannot matter are never made into text.
        var start = state.remainder.startIndex
        while let newline = state.remainder[start...].firstIndex(of: 0x0A) {
            let bytes = state.remainder[start..<newline]
            start = state.remainder.index(after: newline)
            guard CodexRolloutParser.mayMatter(bytes: bytes),
                  let event = CodexRolloutParser.parse(line: String(decoding: bytes, as: UTF8.self))
            else { continue }
            if case .session(let id, _, _) = event {
                state.sessionID = id
            }
            // A log read from the middle has no session line; its file name ends in the id.
            let sessionID = state.sessionID ?? Self.sessionID(fromPath: path)
            events.append((sessionID, event))
        }
        state.remainder = Data(state.remainder[start...])
        files[path] = state
        return events
    }

    /// "rollout-2026-10-07T01-15-31-<id>.jsonl": the id is what follows the time stamp.
    private static func sessionID(fromPath path: String) -> String {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // "rollout", year, month, day and hour, minute, second: six parts before the id.
        let parts = name.split(separator: "-")
        return parts.count > 6 ? parts[6...].joined(separator: "-") : name
    }
}
