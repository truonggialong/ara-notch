import Foundation

/// Tells when Notes writes to its database: watches NoteStore.sqlite and its -wal file, and calls `onChange` on the
/// main actor, at most once per `coalescing` interval. A file that is replaced is reopened after half a second.
public final class NoteStoreWatcher: @unchecked Sendable {
    private let paths: [String]
    private let coalescing: TimeInterval
    private let onChange: @MainActor () -> Void
    private let queue = DispatchQueue(label: "com.aranotch.notes.watcher")
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var pending = false
    private var stopped = false

    public init(url: URL, coalescing: TimeInterval = 1.0, onChange: @escaping @MainActor () -> Void) {
        self.paths = [url.path, url.path + "-wal"]
        self.coalescing = coalescing
        self.onChange = onChange
        queue.async { [self] in for path in paths { watch(path) } }
    }

    deinit { stop() }

    public func stop() {
        queue.sync {
            stopped = true
            for source in sources.values { source.cancel() }
            sources.removeAll()
        }
    }

    // Runs on `queue`.
    private func watch(_ path: String) {
        guard !stopped, sources[path] == nil else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            // The file is not there (yet): look again shortly.
            queue.asyncAfter(deadline: .now() + 0.5) { [self] in watch(path) }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            if !source.data.intersection([.delete, .rename]).isEmpty {
                source.cancel()
                sources[path] = nil
                queue.asyncAfter(deadline: .now() + 0.5) { [self] in
                    watch(path)
                    changed()
                }
            } else {
                changed()
            }
        }
        source.setCancelHandler { close(descriptor) }
        sources[path] = source
        source.resume()
    }

    // Runs on `queue`. The first event starts a window; later events inside it are absorbed.
    private func changed() {
        guard !stopped, !pending else { return }
        pending = true
        queue.asyncAfter(deadline: .now() + coalescing) { [self] in
            pending = false
            guard !stopped else { return }
            let callback = onChange
            Task { @MainActor in callback() }
        }
    }
}
