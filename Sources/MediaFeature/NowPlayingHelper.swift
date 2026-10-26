import Foundation
import MediaCore
import os

/// Reads what is playing through a helper process.
///
/// Since macOS 15.4 the system answers now-playing queries only for Apple-signed processes, so
/// the app cannot ask directly. The helper is `/usr/bin/osascript`, which is Apple-signed,
/// running a short script that asks once a second and prints a line whenever something changed.
/// It needs no permission and quits by itself when the app that started it is gone.
@MainActor
final class NowPlayingHelper {

    var onUpdate: ((NowPlayingUpdate) -> Void)?
    /// Called when the helper is left alone for good: the player cannot be read on this Mac.
    var onGaveUp: (() -> Void)?

    private let log = Logger(subsystem: "com.aranotch.app", category: "media")
    private var process: Process?
    private var buffer = Data()
    private var restarts = HelperRestarts(limit: 3)

    func start() {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // The main queue keeps the chunks in order.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.consume(data) }
            }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperExited(finished) }
            }
        }
        do {
            try process.run()
            self.process = process
        } catch {
            log.error("cannot start the now-playing helper: \(String(describing: error), privacy: .public)")
            if restarts.afterFailedStart() == .giveUp {
                onGaveUp?()
            }
        }
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        process.terminate()
        buffer.removeAll()
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let update = NowPlayingParser.parse(line: line) {
                onUpdate?(update)
            }
        }
    }

    /// The helper is meant to run for as long as the app does; if it dies it is restarted a
    /// few times, then left alone so a broken system interface cannot cause a restart loop.
    private func helperExited(_ finished: Process) {
        guard finished === process else { return }
        process = nil
        buffer.removeAll()
        guard restarts.afterExit() == .restart else {
            log.error("the now-playing helper keeps exiting; giving up")
            onGaveUp?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.start()
        }
    }

    /// JavaScript for Automation. Prints one JSON object per line; see `NowPlayingParser`.
    private static let script = #"""
        ObjC.import('Foundation');
        ObjC.bindFunction('getppid', ['int', []]);
        function run() {
            $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework').load;
            const Request = $.NSClassFromString('MRNowPlayingRequest');
            const out = $.NSFileHandle.fileHandleWithStandardOutput;
            const emit = text => out.writeData($(text + '\n').dataUsingEncoding($.NSUTF8StringEncoding));
            if (!Request) { emit(JSON.stringify({unavailable: true})); return; }
            const parent = $.getppid();
            let last = '', lastArt = '';
            while ($.getppid() === parent) {
                const state = {};
                try {
                    const client = Request.localNowPlayingPlayerPath.client;
                    if (!client.isNil()) state.bundleID = ObjC.unwrap(client.bundleIdentifier);
                    state.isPlaying = !!Request.localIsPlaying;
                    const item = Request.localNowPlayingItem;
                    const info = item.isNil() ? null : item.nowPlayingInfo;
                    if (info && !info.isNil()) {
                        const get = k => { const v = info.objectForKey('kMRMediaRemoteNowPlayingInfo' + k); return v.isNil() ? null : ObjC.unwrap(v); };
                        state.title = get('Title'); state.artist = get('Artist'); state.album = get('Album');
                        if (!state.title) {
                            const asset = info.objectForKey('kMRMediaRemoteNowPlayingInfoAssetURL');
                            if (!asset.isNil()) {
                                // The location can be a reference by file number; its real path has the name.
                                let url = asset.isKindOfClass($.NSURL) ? asset : $.NSURL.URLWithString($(String(ObjC.unwrap(asset.description))));
                                if (!url.isNil() && url.isFileURL) {
                                    const real = url.filePathURL;
                                    const name = ObjC.unwrap((real.isNil() ? url : real).lastPathComponent);
                                    if (name && name.indexOf('id=') !== 0) state.file = name;
                                }
                            }
                        }
                        state.duration = get('Duration'); state.elapsed = get('ElapsedTime'); state.rate = get('PlaybackRate');
                        const stamp = info.objectForKey('kMRMediaRemoteNowPlayingInfoTimestamp');
                        state.timestamp = stamp.isNil() ? null : stamp.timeIntervalSince1970;
                        state.artworkID = get('ArtworkIdentifier') || [state.title, state.artist, state.album].join('|');
                        if (state.artworkID !== lastArt) {
                            const art = info.objectForKey('kMRMediaRemoteNowPlayingInfoArtworkData');
                            if (!art.isNil()) state.artwork = ObjC.unwrap(art.base64EncodedStringWithOptions(0));
                        }
                    }
                } catch (e) { state.error = String(e); }
                const {artwork, ...plain} = state;
                const line = JSON.stringify(plain);
                if (line !== last) { last = line; lastArt = state.artworkID || ''; emit(JSON.stringify(state)); }
                delay(1);
            }
        }
        """#
}
