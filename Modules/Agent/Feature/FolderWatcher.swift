import CoreServices
import Foundation

/// Tells when anything in a folder changes, as the system reports it (FSEvents), instead of
/// looking at the folder again and again. A file is reported once it is written and closed,
/// which is how the hook helper and the status line write theirs.
final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let folder: URL
    private let queue: DispatchQueue
    private let latency: TimeInterval
    /// Called on `queue` with the paths that changed.
    private let onChange: @Sendable ([String]) -> Void

    init(folder: URL, queue: DispatchQueue, latency: TimeInterval = 0.2, onChange: @escaping @Sendable ([String]) -> Void) {
        self.folder = folder
        self.queue = queue
        self.latency = latency
        self.onChange = onChange
    }

    var isRunning: Bool { stream != nil }

    /// Starts watching; false when the folder is not there to watch.
    @discardableResult
    func start() -> Bool {
        guard stream == nil, FileManager.default.fileExists(atPath: folder.path) else { return stream != nil }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            let changed = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            watcher.onChange(Array(changed.prefix(count)))
        }
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context, [folder.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return false }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        return true
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}
