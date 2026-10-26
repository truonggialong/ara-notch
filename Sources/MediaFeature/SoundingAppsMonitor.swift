import AppKit
import CoreAudio
import MediaCore

/// An app that is playing something, as the page shows it.
struct SoundingApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage
    let url: URL

    var id: String { bundleID }

    static func == (lhs: SoundingApp, rhs: SoundingApp) -> Bool {
        lhs.bundleID == rhs.bundleID
    }

    /// The installed app with this bundle id, if there is one.
    @MainActor
    static func lookUp(bundleID: String) -> SoundingApp? {
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let app = SoundingApp(
            bundleID: bundleID, name: FileManager.default.displayName(atPath: url.path),
            icon: NSWorkspace.shared.icon(forFile: url.path), url: url)
        cache[bundleID] = app
        return app
    }

    @MainActor private static var cache: [String: SoundingApp] = [:]
}

/// Tells which apps are sending sound out, whether or not they say what they play. The audio
/// system keeps a list of the processes it serves and whether each is playing; this listens
/// to that list instead of asking over and over, so it costs nothing while all is quiet.
@MainActor
final class SoundingAppsMonitor {
    /// The bundle ids of the apps that count as playing, each time that changes.
    var onChange: (([String]) -> Void)?

    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private var debounce = SoundDebounce()
    private var listListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var timer: Timer?
    private var reported: [String] = []

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    func start() {
        guard listListener == nil else { return }
        // Delivered on the main queue, which is where this class lives.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        var listAddress = Self.address(kAudioHardwarePropertyProcessObjectList)
        guard AudioObjectAddPropertyListenerBlock(Self.system, &listAddress, .main, block) == noErr else { return }
        listListener = block
        refresh()
    }

    func stop() {
        if let listListener {
            var listAddress = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(Self.system, &listAddress, .main, listListener)
        }
        listListener = nil
        var runningAddress = Self.address(kAudioProcessPropertyIsRunningOutput)
        for (process, block) in processListeners {
            AudioObjectRemovePropertyListenerBlock(process, &runningAddress, .main, block)
        }
        processListeners = [:]
        timer?.invalidate()
        timer = nil
        debounce = SoundDebounce()
        report([])
    }

    /// Reads the list again: who is there, who is playing.
    func refresh() {
        guard listListener != nil else { return }
        let processes = Self.processObjects()
        var runningAddress = Self.address(kAudioProcessPropertyIsRunningOutput)

        // Processes come and go; each new one is listened to, each gone one forgotten.
        for process in processes where processListeners[process] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if AudioObjectAddPropertyListenerBlock(process, &runningAddress, .main, block) == noErr {
                processListeners[process] = block
            }
        }
        for (process, block) in processListeners where !processes.contains(process) {
            AudioObjectRemovePropertyListenerBlock(process, &runningAddress, .main, block)
            processListeners[process] = nil
        }

        let sounding = processes.filter(Self.isRunningOutput).compactMap(Self.appBundleID)
        let now = Date()
        debounce.update(sounding: sounding, at: now)
        report(debounce.steady(at: now))

        // A sound counts only once it has lasted, and stops counting a moment after it ends:
        // both happen without any event, so the list is read again at that moment.
        timer?.invalidate()
        timer = nil
        if let next = debounce.nextCheck(after: now) {
            let timer = Timer(timeInterval: next.timeIntervalSince(now) + 0.05, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func report(_ apps: [String]) {
        guard apps != reported else { return }
        reported = apps
        onChange?(apps)
    }

    private static func processObjects() -> [AudioObjectID] {
        var listAddress = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &listAddress, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &listAddress, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var runningAddress = address(kAudioProcessPropertyIsRunningOutput)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &size, &running) == noErr && running != 0
    }

    /// The app a sounding process belongs to: the app macOS holds responsible for the process
    /// (a browser for its helpers, Safari for the system's web process), and failing that the
    /// app its bundle id is named after. Background services with no app are left out.
    private static func appBundleID(_ process: AudioObjectID) -> String? {
        var pidAddress = address(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var pidSize = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid > 0 else { return nil }

        var candidates: [String] = []
        if let responsible = responsiblePID(for: pid),
           let bundleID = NSRunningApplication(processIdentifier: responsible)?.bundleIdentifier {
            candidates.append(bundleID)
        }
        if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            candidates.append(bundleID)
        }
        var bundleAddress = address(kAudioProcessPropertyBundleID)
        var name: CFString = "" as CFString
        var nameSize = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &nameSize, $0)
        }
        if status == noErr, !(name as String).isEmpty {
            candidates.append(SoundingApps.owner(ofBundleID: name as String))
        }

        return candidates.first { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .contains { $0.activationPolicy != .prohibited }
        }
    }

    private typealias ResponsiblePID = @convention(c) (pid_t) -> pid_t

    private static let responsibleFunction: ResponsiblePID? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsiblePID.self)
    }()

    private static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let responsible = responsibleFunction?(pid), responsible > 0 else { return nil }
        return responsible
    }
}
