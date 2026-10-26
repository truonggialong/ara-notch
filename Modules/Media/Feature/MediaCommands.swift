import Foundation
import MediaCore

/// Sends playback commands to whatever app is playing, through the system's media interface.
/// Unlike reading, sending is open to any process.
@MainActor
enum MediaCommands {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

    private static let sendCommand: SendCommand? = {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString)
        else { return nil }
        return unsafeBitCast(pointer, to: SendCommand.self)
    }()

    private typealias SetElapsedTime = @convention(c) (Double) -> Void

    private static let setElapsedTime: SetElapsedTime? = {
        let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL),
              let pointer = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSetElapsedTime" as CFString)
        else { return nil }
        return unsafeBitCast(pointer, to: SetElapsedTime.self)
    }()

    /// Jumps to a position in the track. Returns false when the system interface is missing;
    /// a player that cannot seek ignores the request.
    @discardableResult
    static func seek(to seconds: Double) -> Bool {
        guard let setElapsedTime else { return false }
        setElapsedTime(seconds)
        return true
    }

    /// Returns false when the system interface is missing or refused the command.
    @discardableResult
    static func send(_ command: MediaCommand) -> Bool {
        sendCommand?(command.rawValue, nil) ?? false
    }
}
