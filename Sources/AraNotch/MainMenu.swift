import AppKit

/// The app's main menu. An accessory app shows no menu bar, but standard shortcuts are routed
/// through the main menu, so without one ⌘W, ⌘Q, ⌘C, ⌘V and ⌘A do nothing in its windows.
@MainActor
enum MainMenu {
    /// What ⌘, does: the menu keeps it, as a menu item's target is not kept by the item.
    private static var settingsAction: ActionTarget?

    static func install() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        // ⌘, opens Settings from any window of the app, as in every Mac app.
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(ActionTarget.run), keyEquivalent: ",")
        settings.target = settingsAction
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AraNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, titled: "AraNotch", to: mainMenu)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(editMenu, titled: "Edit", to: mainMenu)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(windowMenu, titled: "Window", to: mainMenu)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    /// Sets what ⌘, does; called once Settings exists.
    static func setOpenSettings(_ action: @escaping @MainActor () -> Void) {
        let target = ActionTarget(action)
        settingsAction = target
        NSApp.mainMenu?.items.first?.submenu?.items.first?.target = target
    }

    private static func add(_ submenu: NSMenu, titled title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        mainMenu.addItem(item)
    }
}

/// A menu item's target that runs a closure.
@MainActor
final class ActionTarget: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @objc func run() {
        action()
    }
}
