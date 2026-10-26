import AppKit
import ClipboardCore
import NotchShell
import UniformTypeIdentifiers

/// The save and open panels of the Backup settings, and the line of text that reports the outcome.
@MainActor
enum BackupPanels {
    private static var fileTypes: [UTType] {
        UTType(filenameExtension: ClipBackup.fileExtension).map { [$0] } ?? []
    }

    /// - Parameter write: writes the backup and returns how many locked boards were left out.
    static func export(reportingTo state: ClipboardSettingsSectionState, write: @escaping (URL) throws -> Int) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = fileTypes
        panel.nameFieldStringValue = defaultFileName(on: Date())
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                state.backupMessage = exportMessage(lockedBoardsLeftOut: try write(url))
            } catch {
                state.backupMessage = message(for: error)
            }
        }
    }

    static func restore(
        reportingTo state: ClipboardSettingsSectionState, read: @escaping (URL) throws -> ClipBackupSummary
    ) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = fileTypes
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                state.backupMessage = message(for: try read(url))
            } catch {
                state.backupMessage = message(for: error)
            }
        }
    }

    /// Locked boards stay out of a backup, so it can be handed around without their passcode;
    /// the message says so, or restoring it on another Mac would lose them without a word.
    static func exportMessage(lockedBoardsLeftOut: Int) -> String {
        lockedBoardsLeftOut == 0
            ? L10n.string("settings.clipboard.backup.exported")
            : String(format: L10n.string("settings.clipboard.backup.exportedWithoutLocked"), lockedBoardsLeftOut)
    }

    static func defaultFileName(on date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "AraNotch \(formatter.string(from: date)).\(ClipBackup.fileExtension)"
    }

    static func message(for summary: ClipBackupSummary) -> String {
        String(
            format: L10n.string("settings.clipboard.backup.restored"),
            summary.itemsAdded, summary.itemsAlreadyPresent, summary.boardsAdded)
    }

    static func message(for error: Error) -> String {
        switch error as? ClipBackupError {
        case .notABackup:
            L10n.string("settings.clipboard.backup.error.notABackup")
        case .newerVersion:
            L10n.string("settings.clipboard.backup.error.newer")
        case nil:
            String(format: L10n.string("settings.clipboard.backup.error.other"), error.localizedDescription)
        }
    }
}
