import AppKit
import Combine
import NotchShell
import SwiftUI
import WindowsCore

/// Observable window settings; every change is written through to the store.
@MainActor
public final class WindowSettings: ObservableObject {
    private let store: WindowSettingsStore

    @Published public var snapEnabled: Bool {
        didSet { store.snapEnabled = snapEnabled }
    }

    @Published public var edgeSnapEnabled: Bool {
        didSet { store.edgeSnapEnabled = edgeSnapEnabled }
    }

    public init(store: WindowSettingsStore) {
        self.store = store
        snapEnabled = store.snapEnabled
        edgeSnapEnabled = store.edgeSnapEnabled
    }
}

/// View-local state of the Windows settings tab.
@MainActor
final class WindowsSettingsState: ObservableObject {
    @Published var isTrusted = WindowMover.isTrusted
    /// Shortcuts the system refused, as written for the user.
    @Published var refusedShortcuts: [String] = []
}

/// Snaps the front window to halves, quarters and more with global shortcuts.
@MainActor
public final class WindowsController {
    private let settings: WindowSettings
    private let hotKeys = GlobalHotKeys()
    private let edgeSnap = EdgeSnapMonitor()
    private let state = WindowsSettingsState()
    private var cancellables = Set<AnyCancellable>()

    public init(settings: WindowSettings) {
        self.settings = settings
    }

    public func start() {
        settings.$snapEnabled
            .sink { [weak self] isEnabled in self?.setShortcutsEnabled(isEnabled) }
            .store(in: &cancellables)
        settings.$edgeSnapEnabled
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.edgeSnap.start()
                } else {
                    self?.edgeSnap.stop()
                }
            }
            .store(in: &cancellables)
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(WindowsSettingsSection(settings: settings, state: state))
    }

    /// Snaps the front window to the zone with this name, as its shortcut would.
    @discardableResult
    public func snap(zoneNamed name: String) -> Bool {
        guard let zone = SnapZone(rawValue: name) else { return false }
        return snap(to: zone)
    }

    private func setShortcutsEnabled(_ isEnabled: Bool) {
        hotKeys.unregisterAll()
        state.refusedShortcuts = []
        guard isEnabled else { return }
        for zone in SnapZone.allCases {
            let shortcut = zone.shortcut
            let registered = hotKeys.register(
                keyCode: shortcut.keyCode, modifiers: GlobalHotKeys.Modifiers(rawValue: shortcut.modifiers.rawValue)
            ) { [weak self] in
                self?.snap(to: zone)
            }
            if !registered {
                state.refusedShortcuts.append(zone.shortcut.display)
            }
        }
    }

    @discardableResult
    private func snap(to zone: SnapZone) -> Bool {
        let done = WindowMover.snap(to: zone)
        if !done {
            NSSound.beep()
        }
        return done
    }
}

/// The Windows tab of the Settings window.
struct WindowsSettingsSection: View {
    @ObservedObject var settings: WindowSettings
    @ObservedObject var state: WindowsSettingsState

    var body: some View {
        Toggle(isOn: $settings.snapEnabled) {
            Text(L10n.string("settings.windows.snap"))
            if settings.snapEnabled, !state.refusedShortcuts.isEmpty {
                Text(String(format: L10n.string("settings.windows.refused"), state.refusedShortcuts.joined(separator: ", ")))
                    .font(.caption)
                    .foregroundStyle(AraPalette.warning)
            } else {
                AraSettingsNote(L10n.string("settings.windows.snap.note"))
            }
        }
        if settings.snapEnabled {
            DisclosureGroup(L10n.string("settings.windows.shortcuts")) {
                ForEach(SnapZone.allCases, id: \.self) { zone in
                    LabeledContent(L10n.string("settings.windows.zone.\(zone.rawValue)")) {
                        Text(zone.shortcut.display)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        Toggle(isOn: $settings.edgeSnapEnabled) {
            Text(L10n.string("settings.windows.edgeSnap"))
            AraSettingsNote(L10n.string("settings.windows.edgeSnap.note"))
        }
    }
}
