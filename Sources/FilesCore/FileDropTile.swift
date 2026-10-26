import Foundation

/// The actions shown as places to drop while files are dragged over the Files page: letting
/// go over one adds the files and does it at once.
public enum FileDropTile: String, CaseIterable, Sendable {
    case airDrop, resize, compress, pdf

    /// What the tile does to the dropped files; AirDrop is not a file action and has none.
    public var action: FileAction? {
        switch self {
        case .airDrop: nil
        case .resize: .resize(percent: 50)
        case .compress: .compress
        case .pdf: .makePDF
        }
    }
}

/// How far an action over several files has got.
public enum FileProgress {
    /// A whole percentage from 0 to 100.
    public static func percent(done: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return min(max(Int((Double(done) / Double(total) * 100).rounded()), 0), 100)
    }
}
