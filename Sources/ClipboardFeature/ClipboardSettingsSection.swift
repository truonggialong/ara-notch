import AppKit
import ClipboardCore
import Combine
import NotchShell
import SwiftUI

/// View-local state of the section. An object instead of `@State`, because `@State` is a macro
/// in the macOS 27 SDK and its compiler plugin ships only with Xcode, not the Command Line Tools.
@MainActor
final class ClipboardSettingsSectionState: ObservableObject {
    @Published var isTrusted = Paster.isTrusted
    @Published var isConfirmingClear = false
    /// The part of the history the user asked to clear and has yet to confirm.
    @Published var pendingClearRange: ClearRange?
    /// Outcome of the last backup or restore, shown under the buttons.
    @Published var backupMessage: String?
}

/// Settings › Clipboard: recording, how long clips are kept, pasting.
struct ClipboardSettingsSection: View {
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var state: ClipboardSettingsSectionState
    @ObservedObject var shortcuts: ShortcutCenter
    /// For the list of boards.
    @ObservedObject var model: ClipboardViewModel
    let onPause: (CapturePause) -> Void
    let onResume: () -> Void

    private static let maxItemsChoices = [50, 100, 200, 500, 1000]

    /// "Recording", "Paused until 14:30" or "Paused until turned back on".
    private var pauseStatus: String {
        switch RecordingState(isPaused: settings.isPaused, pausedUntil: settings.pausedUntil, now: Date()) {
        case .recording:
            return L10n.string("settings.clipboard.recording.on")
        case .paused:
            return L10n.string("settings.clipboard.recording.paused")
        case .pausedUntil(let end):
            return String(format: L10n.string("settings.clipboard.recording.pausedUntil"), Self.pauseEndFormatter.string(from: end))
        }
    }

    private static let pauseEndFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    /// Apps with windows that are running now, as candidates for the ignore list.
    private static func runningApps(excluding ignored: [String]) -> [(name: String, bundleID: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, bundleID: String)? in
                guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier,
                      !ignored.contains(bundleID)
                else { return nil }
                return (app.localizedName ?? bundleID, bundleID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The app's display name when it is installed; otherwise the bundle identifier itself.
    private static func appName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
    var body: some View {
        Section(L10n.string("settings.section.clipboard")) {
            // What is happening now as the line's name; the button beside it changes it.
            LabeledContent {
                HStack {
                    if settings.isPausedNow {
                        Button(L10n.string("settings.clipboard.resume")) { onResume() }
                    }
                    Menu(L10n.string("settings.clipboard.pause")) {
                        ForEach(CapturePause.allCases, id: \.self) { pause in
                            Button(L10n.string("settings.clipboard.pause.\(pause.rawValue)")) { onPause(pause) }
                        }
                    }
                    .fixedSize()
                }
            } label: {
                Text(pauseStatus)
                    .foregroundStyle(settings.isPausedNow ? AnyShapeStyle(AraPalette.warning) : AnyShapeStyle(.primary))
            }
            Picker(L10n.string("settings.clipboard.retention"), selection: $settings.retention) {
                ForEach(ClipRetention.allCases, id: \.self) { retention in
                    Text(L10n.string("settings.clipboard.retention.\(retention.rawValue)")).tag(retention)
                }
            }
            Picker(selection: $settings.maxItems) {
                ForEach(Self.maxItemsChoices, id: \.self) { count in
                    Text(String(format: L10n.string("settings.clipboard.maxItems.count"), count)).tag(count)
                }
            } label: {
                Text(L10n.string("settings.clipboard.maxItems"))
                AraSettingsNote(L10n.string("settings.clipboard.maxItems.note"))
            }
            // Off, or which sound: one choice instead of a switch, a list and a volume.
            Picker(L10n.string("settings.clipboard.copyFeedback"), selection: Binding(
                get: { settings.copyFeedback ? settings.copySound.rawValue : "" },
                set: { value in
                    settings.copyFeedback = !value.isEmpty
                    if let sound = CopySound(rawValue: value) {
                        settings.copySound = sound
                        // The sound chosen is heard at once.
                        let player = NSSound(named: sound.systemName)?.copy() as? NSSound
                        player?.volume = Float(settings.copySoundVolume)
                        player?.play()
                    }
                }
            )) {
                Text(L10n.string("settings.off")).tag("")
                ForEach(CopySound.allCases, id: \.self) { sound in
                    Text(sound.systemName).tag(sound.rawValue)
                }
            }
            Toggle(L10n.string("settings.clipboard.copySign"), isOn: $settings.copySign)
            Toggle(isOn: $settings.pasteOnClick) {
                Text(L10n.string("settings.clipboard.pasteOnClick"))
                AraSettingsNote(L10n.string("settings.clipboard.pasteOnClick.note"))
            }
            Toggle(isOn: $settings.skipsSensitiveText) {
                Text(L10n.string("settings.clipboard.skipsSensitive"))
                AraSettingsNote(L10n.string("settings.clipboard.skipsSensitive.note"))
            }
            Toggle(isOn: $settings.vaultTouchID) {
                Text(L10n.string("settings.clipboard.vaultTouchID"))
                AraSettingsNote(L10n.string("settings.clipboard.vaultTouchID.note"))
            }
        }

        Section(L10n.string("settings.shortcuts.numberRows")) {
            ForEach(ClipboardNumberRows.all, id: \.self) { row in
                ShortcutNumberRowPicker(center: shortcuts, row: row)
            }
            // Which board only matters once pinned items are pasted by number.
            if shortcuts.numberRowModifiers[ClipboardNumberRows.pinned] != nil {
                Picker(L10n.string("settings.clipboard.quickPasteBoard"), selection: $settings.quickPasteBoardName) {
                    Text(L10n.string("settings.clipboard.quickPasteBoard.first")).tag("")
                    ForEach(model.boards) { board in
                        Text(board.name).tag(board.name)
                    }
                }
            }
        }

        Section(L10n.string("settings.clipboard.ignoredApps")) {
            if settings.ignoredBundleIDs.isEmpty {
                Text(L10n.string("settings.clipboard.ignoredApps.empty"))
                    .foregroundStyle(.secondary)
            }
            ForEach(settings.ignoredBundleIDs, id: \.self) { bundleID in
                HStack {
                    Text(Self.appName(for: bundleID))
                    Spacer()
                    Button(L10n.string("settings.clipboard.ignoredApps.remove")) {
                        settings.ignoredBundleIDs.removeAll { $0 == bundleID }
                    }
                }
            }
            Menu(L10n.string("settings.clipboard.ignoredApps.add")) {
                ForEach(Self.runningApps(excluding: settings.ignoredBundleIDs), id: \.bundleID) { app in
                    Button(app.name) { settings.ignoredBundleIDs.append(app.bundleID) }
                }
            }
            .fixedSize()
        }
    }
}

/// The clipboard's tools in Settings › Tools and shortcuts: the floating panel and a new note.
struct ClipboardToolSettings: View {
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var shortcuts: ShortcutCenter

    var body: some View {
        ShortcutRow(
            center: shortcuts, action: .clipboardPanel, titleKey: "settings.clipboard.hotKey",
            noteKey: "settings.clipboard.hotKey.note", isOn: $settings.hotKeyEnabled)
        ShortcutRow(center: shortcuts, action: .newNote, titleKey: "shortcut.newNote", noteKey: "settings.clipboard.newNote.note")
    }
}

/// What the clipboard keeps and where, at the foot of Settings › Clipboard: link previews,
/// text in pictures, backups, clearing the history.
struct ClipboardDataSettings: View {
    @ObservedObject var settings: ClipboardSettings
    @ObservedObject var state: ClipboardSettingsSectionState
    let onClearRange: (ClearRange) -> Void
    let onClearHistory: () -> Void
    let onExportBackup: () -> Void
    let onRestoreBackup: () -> Void

    var body: some View {
        Toggle(isOn: $settings.linkPreviews) {
            Text(L10n.string("settings.clipboard.linkPreviews"))
            AraSettingsNote(L10n.string("settings.clipboard.linkPreviews.note"))
        }
        Toggle(isOn: $settings.readsTextInImages) {
            Text(L10n.string("settings.clipboard.readsTextInImages"))
            AraSettingsNote(L10n.string("settings.clipboard.readsTextInImages.note"))
        }
        // Said the way round a person thinks of it: on means the history is backed up.
        Toggle(isOn: Binding(get: { !settings.excludedFromBackup }, set: { settings.excludedFromBackup = !$0 })) {
            Text(L10n.string("settings.clipboard.timeMachine"))
            AraSettingsNote(L10n.string("settings.clipboard.timeMachine.note"))
        }
        LabeledContent {
            HStack {
                Button(L10n.string("settings.clipboard.backup.export"), action: onExportBackup)
                Button(L10n.string("settings.clipboard.backup.restore"), action: onRestoreBackup)
            }
        } label: {
            Text(L10n.string("settings.clipboard.backup"))
            AraSettingsNote(state.backupMessage ?? L10n.string("settings.clipboard.backup.note"))
        }
        LabeledContent {
            Menu(L10n.string("settings.clipboard.clearPart.choose")) {
                ForEach(ClearRange.allCases, id: \.self) { range in
                    Button(L10n.string("settings.clipboard.clearRange.\(range.rawValue)")) {
                        state.pendingClearRange = range
                    }
                }
                Divider()
                Button(L10n.string("settings.clipboard.clear"), role: .destructive) {
                    state.isConfirmingClear = true
                }
            }
            .fixedSize()
        } label: {
            Text(L10n.string("settings.clipboard.clearPart"))
                .foregroundStyle(AraPalette.danger)
            AraSettingsNote(L10n.string("settings.clipboard.clearPart.note"))
        }
        .confirmationDialog(
            state.pendingClearRange.map { L10n.string("settings.clipboard.clearRange.\($0.rawValue)") } ?? "",
            isPresented: Binding(get: { state.pendingClearRange != nil }, set: { if !$0 { state.pendingClearRange = nil } })
        ) {
            Button(L10n.string("settings.clipboard.clear.confirm.action"), role: .destructive) {
                if let range = state.pendingClearRange {
                    onClearRange(range)
                }
                state.pendingClearRange = nil
            }
            Button(L10n.string("settings.cancel"), role: .cancel) { state.pendingClearRange = nil }
        } message: {
            Text(L10n.string("settings.clipboard.clearRange.body"))
        }
        .confirmationDialog(L10n.string("settings.clipboard.clear.confirm.title"), isPresented: $state.isConfirmingClear) {
            Button(L10n.string("settings.clipboard.clear.confirm.action"), role: .destructive, action: onClearHistory)
            Button(L10n.string("settings.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.string("settings.clipboard.clear.confirm.body"))
        }
    }
}

/// Letting AI agents read the history, in Settings › Agents.
struct ClipboardAgentAccessSettings: View {
    @ObservedObject var settings: ClipboardSettings

    /// The command that adds the helper to Claude Code; other agents take the same program path.
    private static var mcpCommand: String {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/aranotch-mcp").path
        return "claude mcp add aranotch-clipboard -- \"\(helper)\""
    }

    var body: some View {
        Toggle(isOn: $settings.mcpEnabled) {
            Text(L10n.string("settings.clipboard.mcp.enabled"))
            AraSettingsNote(L10n.string("settings.clipboard.mcp.note"))
        }
        if settings.mcpEnabled {
            LabeledContent {
                Button(L10n.string("clipboard.menu.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.mcpCommand, forType: .string)
                }
            } label: {
                Text(L10n.string("settings.clipboard.mcp.command"))
                Text(Self.mcpCommand)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
    }
}
