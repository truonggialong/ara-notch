import AppKit
import NotchCore

/// Opens the app again, for a change that takes effect only at launch (the language).
@MainActor
enum AppRelauncher {
    /// Quits, and has a shell open the app once this copy is gone: two copies at once would
    /// fight over the shortcuts and the notch. `open` rather than the executable itself, so
    /// macOS starts the app as it starts it by hand.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let arguments = AppLanguage.relaunchArguments(from: CommandLine.arguments)
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let app = "'" + Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; /usr/bin/open -n \(app) --args \(arguments)"
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", script]
        do {
            try shell.run()
        } catch {
            NSSound.beep()
            return
        }
        NSApp.terminate(nil)
    }
}
