import Foundation

/// How a picture is placed in the picture area of its card.
public enum ClipThumbnailPlacement: Equatable, Sendable {
    /// The whole picture, scaled to fit; nothing is cut off.
    case whole
    /// Fills the area, starting at the picture's top: for a page so long that the whole of it would be a sliver.
    case filledFromTop
    /// Fills the area, starting at the picture's leading edge: for a strip so wide that the whole of it would be a sliver.
    case filledFromLeading

    /// The whole picture is too thin to make out once it takes less than this share of the area's width or height.
    static let sliverShare: CGFloat = 0.2

    public init(pictureSize: CGSize, in area: CGSize) {
        guard pictureSize.width > 0, pictureSize.height > 0, area.width > 0, area.height > 0 else {
            self = .whole
            return
        }
        let scale = min(area.width / pictureSize.width, area.height / pictureSize.height)
        if pictureSize.width * scale < area.width * Self.sliverShare {
            self = .filledFromTop
        } else if pictureSize.height * scale < area.height * Self.sliverShare {
            self = .filledFromLeading
        } else {
            self = .whole
        }
    }
}
