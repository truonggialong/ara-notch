import Foundation

/// Whether the clipboard history goes into Time Machine backups. Everything copied is in it,
/// passwords copied from apps that do not mark them included, so by default it does not.
public enum BackupExclusion {
    /// Marks the folder, and with it everything in it, as left out of backups or not.
    public static func apply(_ excluded: Bool, to directory: URL) throws {
        var url = URL(fileURLWithPath: directory.path, isDirectory: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try url.setResourceValues(values)
    }
}
