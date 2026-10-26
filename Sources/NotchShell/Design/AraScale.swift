import SwiftUI

private struct AraScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

public extension EnvironmentValues {
    /// How much larger than their layout the notch's pages are shown. Views multiply their
    /// fixed sizes by it, so the notch is laid out at the size it is shown and its text is
    /// drawn sharp; enlarging a drawing made at the layout size blurred the text on displays
    /// that are not Retina. 1 outside the notch (Settings, the Library, the clipboard panel).
    var araScale: CGFloat {
        get { self[AraScaleKey.self] }
        set { self[AraScaleKey.self] = newValue }
    }
}
