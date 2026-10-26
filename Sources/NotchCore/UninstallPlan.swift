import Foundation

/// What taking AraNotch off a Mac removes, besides the app itself: its hooks and status line
/// are taken out of Claude Code's settings (which are changed, never removed), the caches
/// go, and with them, when the user asks, the clipboard history, the agent data and the
/// settings. Dragging the app to the Trash left all of that behind.
public struct UninstallPlan: Equatable, Sendable {
    public let home: URL
    public let bundleID: String
    public let removesData: Bool

    public init(home: URL, bundleID: String, removesData: Bool) {
        self.home = home
        self.bundleID = bundleID
        self.removesData = removesData
    }

    private var library: URL { home.appendingPathComponent("Library", isDirectory: true) }

    /// Claude Code's settings, to take the hooks and the status line out of.
    public var claudeSettings: URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    /// The app's settings go with its data.
    public var removesSettings: Bool { removesData }

    /// Files and folders to remove.
    public var removals: [URL] {
        let support = library.appendingPathComponent("Application Support/AraNotch", isDirectory: true)
        return [
            // The hook helper is called by nothing once the hooks are out.
            removesData ? support : support.appendingPathComponent("bin", isDirectory: true),
            library.appendingPathComponent("Caches/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
            library.appendingPathComponent("Saved Application State/\(bundleID).savedState", isDirectory: true),
        ]
    }
}
