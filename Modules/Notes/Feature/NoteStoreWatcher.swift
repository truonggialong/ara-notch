import Foundation

/// Tells when Notes writes to its database: watches NoteStore.sqlite and its -wal file, and calls `onChange` on the
/// main actor, at most once per `coalescing` interval. A file that is replaced is reopened after half a second.
public final class NoteStoreWatcher: @unchecked Sendable {
    private let paths: [String]
    private let coalescing: TimeInterval
    private let onChange: @MainActor () -> Void
    private let queue = DispatchQueue(label: "com.aranotch.notes.watcher")
    // State is guarded by `lock`, so stop() and deinit are safe from any thread, including `queue` itself.
    private let lock = NSLock()
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
        lock.lock()
        stopped = true
        let old = Array(sources.values)
        sources.removeAll()
        lock.unlock()
        for source in old { source.cancel() }
    }

    // Runs on `queue`.
    private func watch(_ path: String) {
        lock.lock()
        let skip = stopped || sources[path] != nil
        lock.unlock()
        guard !skip else { return }
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
                lock.lock()
                sources[path] = nil
                lock.unlock()
                queue.asyncAfter(deadline: .now() + 0.5) { [self] in
                    watch(path)
                    changed()
                }
            } else {
                changed()
            }
        }
        source.setCancelHandler { close(descriptor) }
        lock.lock()
        if stopped {
            lock.unlock()
            source.cancel()
            source.resume()
            return
        }
        sources[path] = source
        lock.unlock()
        source.resume()
    }

    // Runs on `queue`. The first event starts a window; later events inside it are absorbed.
    private func changed() {
        lock.lock()
        let skip = stopped || pending
        if !skip { pending = true }
        lock.unlock()
        guard !skip else { return }
        queue.asyncAfter(deadline: .now() + coalescing) { [self] in
            lock.lock()
            pending = false
            let isStopped = stopped
            lock.unlock()
            guard !isStopped else { return }
            let callback = onChange
            Task { @MainActor in callback() }
        }
    }
}
