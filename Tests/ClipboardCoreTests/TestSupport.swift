import Foundation
@testable import ClipboardCore

/// Builds a stored item for tests that only care about a few fields.
func makeItem(
    id: Int64 = 1, kind: ClipKind = .text, text: String = "",
    appName: String? = nil, bundleID: String? = nil
) -> ClipItem {
    ClipItem(
        id: id, kind: kind, text: text, blobName: nil,
        source: ClipSource(bundleID: bundleID, appName: appName),
        createdAt: Date(timeIntervalSince1970: 0), lastUsedAt: Date(timeIntervalSince1970: 0),
        byteSize: text.utf8.count)
}
