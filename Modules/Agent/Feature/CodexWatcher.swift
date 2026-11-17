import AgentCore
import CoreServices
import Foundation

/// Follows Codex by reading the session logs it writes itself (`~/.codex/sessions`). Nothing
/// of Codex is changed. Only lines that say how a session is doing are decoded; lines that
/// hold conversation content are skipped unread.
///
/// The logs are read on a queue of their own, never on the main thread: at the start the
/// recent ones are read whole, and a few megabytes would stall the notch. The system reports a
/// log as it is closed, and Codex keeps its log open for the whole session, so logs written in
/// the last half hour are also read again every two seconds (`AgentPacing`).
@MainActor
final class CodexWatcher {
    /// Session events, with the Codex session id they belong to. `isHistory` is true for what
    /// was already on disk when watching began: it is known, not announced.
    var onEvents: ((_ events: [(sessionID: String, event: CodexRolloutEvent)], _ isHistory: Bool) -> Void)?

    let directory: URL
    private var reader: CodexLogReader?

    init(directory: URL? = nil) {
        self.directory = directory
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
    }

    var isRunning: Bool { reader != nil }

    func start() {
        guard reader == nil, FileManager.default.fileExists(atPath: directory.path) else { return }
        let reader = CodexLogReader(directory: directory) { [weak self] events, isHistory in
            Task { @MainActor in self?.onEvents?(events, isHistory) }
        }
        reader.start()
        self.reader = reader
    }

    func stop() {
        reader?.stop()
        reader = nil
    }
}

/// The reading itself, confined to its own queue.
private final class CodexLogReader: @unchecked Sendable {
    /// Logs not touched for this long are not opened at all.
    private static let recentWindow: TimeInterval = 12 * 3600

    private let directory: URL
    private let deliver: @Sendable ([(sessionID: String, event: CodexRolloutEvent)], Bool) -> Void
    private let queue = DispatchQueue(label: "aranotch.codex-logs", qos: .utility)
    private var watcher: FolderWatcher?
    private var poller: DispatchSourceTimer?
    private var isPolling = false
    private var stopped = false
    /// How far each log was read, and the session it belongs to once that is known.
    private var files: [String: (offset: UInt64, remainder: Data, sessionID: String?)] = [:]
    /// When each log last grew, for the ones read again while Codex holds them open.
    private var lastWrites: [String: Date] = [:]

    init(directory: URL, deliver: @escaping @Sendable ([(sessionID: String, event: CodexRolloutEvent)], Bool) -> Void) {
        self.directory = directory
        self.deliver = deliver
    }

    func start() {
        queue.async { [self] in
            scanRecent()
            let watcher = FolderWatcher(folder: directory, queue: queue, latency: 0.5) { [weak self] paths in
                self?.read(paths: paths, isHistory: false)
            }
            watcher.start()
            self.watcher = watcher
            let poller = DispatchSource.makeTimerSource(queue: queue)
            poller.setEventHandler { [weak self] in self?.pollOpenLogs() }
            poller.schedule(deadline: .distantFuture)
            poller.resume()
            self.poller = poller
            updatePolling()
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            watcher?.stop()
            watcher = nil
            poller?.cancel()
            poller = nil
            files = [:]
            lastWrites = [:]
        }
    }

    private func pollOpenLogs() {
        read(paths: AgentPacing.openLogs(lastWrites, now: Date()), isHistory: false)
    }

    /// Polls only while some log was written in the last half hour.
    private func updatePolling() {
        guard let poller else { return }
        let wanted = !AgentPacing.openLogs(lastWrites, now: Date()).isEmpty
        guard wanted != isPolling else { return }
        isPolling = wanted
        if wanted {
            poller.schedule(
                deadline: .now() + AgentPacing.openLogPoll, repeating: AgentPacing.openLogPoll, leeway: .milliseconds(500))
        } else {
            poller.schedule(deadline: .distantFuture)
        }
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
        for (path, modified) in recent {
            lastWrites[path] = modified
        }
        // Oldest first, so the newest log's rate limits are the ones left standing.
        read(paths: recent.sorted { $0.modified < $1.modified }.map(\.path), isHistory: true)
    }

    private func read(paths: [String], isHistory: Bool) {
        guard !stopped else { return }
        var events: [(sessionID: String, event: CodexRolloutEvent)] = []
        for path in paths where path.hasSuffix(".jsonl") {
            let found = readNew(in: path)
            events += found.events
            if found.grew { lastWrites[path] = Date() }
        }
        if !events.isEmpty {
            deliver(events, isHistory)
        }
        updatePolling()
    }

    /// Reads what was appended to a log since the last time; `grew` when there was anything.
    private func readNew(in path: String) -> (events: [(sessionID: String, event: CodexRolloutEvent)], grew: Bool) {
        guard let handle = FileHandle(forReadingAtPath: path) else { return ([], false) }
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
            return ([], false)
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
        return (events, true)
    }

    /// "rollout-2026-10-07T01-15-31-<id>.jsonl": the id is what follows the time stamp.
    private static func sessionID(fromPath path: String) -> String {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // "rollout", year, month, day and hour, minute, second: six parts before the id.
        let parts = name.split(separator: "-")
        return parts.count > 6 ? parts[6...].joined(separator: "-") : name
    }
}
