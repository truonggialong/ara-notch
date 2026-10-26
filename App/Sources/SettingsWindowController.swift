import AppKit
import NotchShell
import SwiftUI

/// Owns the single Settings window and brings it to the front on demand. The window is made
/// the first time it is shown: making it at launch took about a fifth of a second of a launch
/// that has the notch to put up, for a window most launches never show.
@MainActor
final class SettingsWindowController {
    private let tabs: [SettingsTab]
    private let navigation: SettingsNavigation
    private let tabIDs: [String]
    private lazy var window: NSWindow = makeWindow()

    init(tabs: [SettingsTab]) {
        self.tabs = tabs
        tabIDs = tabs.map(\.id)
        navigation = SettingsNavigation(selectedTabID: tabs.first?.id ?? "")
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(navigation: navigation, tabs: tabs))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = L10n.string("settings.title")
        window.isReleasedWhenClosed = false
        // The title bar is part of the ground the cards lie on.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = AraPalette.nsGround
        window.setContentSize(NSSize(width: SettingsView.size.width, height: SettingsView.size.height))
        window.center()
        return window
    }

    /// - Parameter tabID: the tab to switch to; nil or an unknown id keeps the current tab.
    func show(tabID: String? = nil, query: String? = nil) {
        if let tabID, tabIDs.contains(tabID) {
            navigation.selectedTabID = tabID
        }
        if let query {
            navigation.query = query
        }
        // An accessory app is not frontmost by default, so activate before showing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
