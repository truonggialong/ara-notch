import SwiftUI

/// A small caption: what the things under or beside it are.
public struct AraLabel: View {
    @Environment(\.araScale) private var ui
    let text: String
    /// True for a caption written straight on the ground of a window, outside any card.
    var isOnGround: Bool
    @Environment(\.araHue) private var hue

    public init(_ text: String, isOnGround: Bool = false) {
        self.text = text
        self.isOnGround = isOnGround
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 10 * ui, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(isOnGround ? AraPalette.label : AraPalette.label(in: hue))
    }
}

/// One line of facts: what something is, then a detail about it, as "Safari · 2 min ago".
public struct AraFactRow: View {
    @Environment(\.araScale) private var ui
    let label: String
    let value: String
    @Environment(\.araHue) private var hue

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 4 * ui) {
            Text(label)
                .font(.system(size: 10 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.label(in: hue))
                .lineLimit(1)
            Text("·")
                .font(.system(size: 10 * ui, weight: .semibold))
                .opacity(0.45)
            Text(value)
                .font(.system(size: 10 * ui, weight: .medium))
                .opacity(0.68)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
