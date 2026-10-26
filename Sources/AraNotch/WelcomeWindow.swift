import AppKit
import ApplicationServices
import EventKit
import NotchCore
import NotchShell
import SwiftUI

/// One permission the app can use, and whether macOS has granted it.
struct WelcomePermission: Identifiable {
    let id: String
    let icon: AraIcon
    let titleKey: String
    let reasonKey: String
    /// The pane of System Settings where the permission is given.
    let settingsURL: String
    let isGranted: () -> Bool
}

/// The first-run guide: what the app does in three lines, and which permissions it can use.
/// Shown once after installing, and again from the About page.
struct WelcomeView: View {
    let panelShortcut: String
    let permissions: [WelcomePermission]
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // The app's own card: its icon and the words beside it.
            HStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.string("welcome.title"))
                        .font(AraType.display(28))
                    Text(L10n.string("welcome.subtitle"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AraTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .araCard(radius: 20)

            HStack(alignment: .top, spacing: 10) {
                step(glyph: .mark, titleKey: "welcome.step.notch.title", bodyKey: "welcome.step.notch.body", keys: nil)
                step(glyph: .clipboard, titleKey: "welcome.step.panel.title", bodyKey: "welcome.step.panel.body", keys: panelShortcut)
                step(glyph: .files, titleKey: "welcome.step.files.title", bodyKey: "welcome.step.files.body", keys: nil)
            }
            // As tall as the tallest of the three, so they line up.
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                AraLabel(L10n.string("welcome.permissions"), isOnGround: true)
                    .padding(.leading, 4)
                // Asked again every second, so a permission given in System Settings shows here at once.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 5) {
                        ForEach(permissions) { permission in
                            permissionRow(permission)
                        }
                    }
                }
            }

            AraPillButton(L10n.string("welcome.done"), icon: .confirm, isProminent: true, action: onDone)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .padding(.top, 8)
        .frame(width: 620)
        .foregroundStyle(AraPalette.onGround)
        .background(AraPalette.ground)
    }

    private func step(glyph: AraGlyph, titleKey: String, bodyKey: String, keys: String?) -> some View {
        VStack(spacing: 7) {
            AraGlyphView(glyph, size: 26)
                .foregroundStyle(AraPalette.ink)
                .frame(width: 46, height: 46)
                .araSurface(Circle(), level: .raised)
            Text(L10n.string(titleKey))
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
            if let keys {
                Text(keys)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(AraPalette.hairline, lineWidth: 1)
                    }
            }
            Text(L10n.string(bodyKey))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .araCard()
    }

    private func permissionRow(_ permission: WelcomePermission) -> some View {
        let isGranted = permission.isGranted()
        return HStack(spacing: 10) {
            permission.icon.image
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string(permission.titleKey))
                    .font(.system(size: 12, weight: .medium))
                Text(L10n.string(permission.reasonKey))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if isGranted {
                Label(L10n.string("welcome.permission.granted"), systemImage: AraIcon.completed.symbolName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AraPalette.value)
            } else {
                AraPillButton(L10n.string("welcome.permission.open"), icon: .settings) {
                    if let url = URL(string: permission.settingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .araCard(radius: AraTheme.rowRadius)
    }
}

/// Owns the welcome window.
@MainActor
final class WelcomeWindowController {
    private var window: NSWindow?
    private let settings: ShellSettings
    private let panelShortcut: () -> String

    init(settings: ShellSettings, panelShortcut: @escaping () -> String) {
        self.settings = settings
        self.panelShortcut = panelShortcut
    }

    /// Shows the guide the first time the app is opened by hand.
    func showIfFirstRun() {
        guard !settings.hasSeenWelcome else { return }
        show()
    }

    func show() {
        settings.hasSeenWelcome = true
        if window == nil {
            let view = WelcomeView(panelShortcut: panelShortcut(), permissions: Self.permissions) { [weak self] in
                self?.window?.close()
            }
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.backgroundColor = AraPalette.nsGround
            window.title = ""
            window.isReleasedWhenClosed = false
            window.setContentSize(host.view.fittingSize)
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static let privacy = "x-apple.systempreferences:com.apple.preference.security?"

    /// What each permission is for is said in one line; none of them is needed to start.
    static var permissions: [WelcomePermission] {
        [
            WelcomePermission(
                id: "accessibility", icon: .paste, titleKey: "welcome.permission.accessibility",
                reasonKey: "welcome.permission.accessibility.reason", settingsURL: privacy + "Privacy_Accessibility"
            ) { AXIsProcessTrusted() },
            WelcomePermission(
                id: "screen", icon: .captureRegion, titleKey: "welcome.permission.screen",
                reasonKey: "welcome.permission.screen.reason", settingsURL: privacy + "Privacy_ScreenCapture"
            ) { CGPreflightScreenCaptureAccess() },
            WelcomePermission(
                id: "calendar", icon: .calendar, titleKey: "welcome.permission.calendar",
                reasonKey: "welcome.permission.calendar.reason", settingsURL: privacy + "Privacy_Calendars"
            ) { EKEventStore.authorizationStatus(for: .event) == .fullAccess },
            WelcomePermission(
                id: "reminders", icon: .reminders, titleKey: "welcome.permission.reminders",
                reasonKey: "welcome.permission.reminders.reason", settingsURL: privacy + "Privacy_Reminders"
            ) { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess },
        ]
    }
}
