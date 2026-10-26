import AgentCore
import Foundation

/// Follows the file the hook helper appends to and hands over each new event.
@MainActor
final class AgentEventSpool {
    private static let maxFileSize: UInt64 = 1_000_000
    private static let keptLines = 300

    var onEvents: (([AgentEvent]) -> Void)?
    /// Called on every check, for other small files that are watched at the same pace.
    var onTick: (() -> Void)?

    let file: URL
    private var offset: UInt64 = 0
    private var remainder = Data()
    private var timer: Timer?

    init(file: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        self.file = file ?? base.appendingPathComponent("AraNotch/Agents/events.jsonl")
    }

    /// Reads what is already there (sessions that began before the app did), then checks for
    /// more once a second.
    func start() {
        guard timer == nil else { return }
        trimIfLarge()
        readNew()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.readNew() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func readNew() {
        onTick?()
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size < offset {
            // The file was replaced or trimmed; start over.
            offset = 0
            remainder.removeAll()
        }
        guard size > offset, (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty
        else { return }
        offset += UInt64(data.count)
        remainder.append(data)

        var events: [AgentEvent] = []
        while let newline = remainder.firstIndex(of: 0x0A) {
            let line = String(decoding: remainder[remainder.startIndex..<newline], as: UTF8.self)
            remainder.removeSubrange(remainder.startIndex...newline)
            if let event = AgentEventParser.parse(line: line) {
                events.append(event)
            }
        }
        if !events.isEmpty {
            onEvents?(events)
        }
        // A long run with busy agents grows the file; once all of it has been read, it is cut
        // down to its newest lines then and there, not only at the next launch.
        if offset > Self.maxFileSize, remainder.isEmpty {
            trimIfLarge()
            offset = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? UInt64 ?? 0
        }
    }

    /// The helper only ever appends. A long file is cut down to its newest lines, at launch
    /// and whenever it has grown past the limit and been read to its end.
    private func trimIfLarge() {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size] as? UInt64,
              size > Self.maxFileSize, let text = try? String(contentsOf: file, encoding: .utf8)
        else { return }
        let lines = text.split(separator: "\n").suffix(Self.keptLines)
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
