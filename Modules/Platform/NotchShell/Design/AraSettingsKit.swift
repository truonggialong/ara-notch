import SwiftUI

/// A group of related switches in Settings shown as one row of chips: a lit chip is on.
/// Several on-or-off choices of one kind (which notices to show, which tiles the overview has)
/// take one line instead of one line each.
public struct AraChipRow: View {
    public struct Chip: Identifiable {
        public let id: String
        public let title: String
        public let isOn: Binding<Bool>

        public init(id: String, title: String, isOn: Binding<Bool>) {
            self.id = id
            self.title = title
            self.isOn = isOn
        }
    }

    let titleKey: String
    let noteKey: String?
    let chips: [Chip]
    /// A line under the chips, for what one of them needs said.
    let footnoteKey: String?

    public init(titleKey: String, noteKey: String? = nil, chips: [Chip], footnoteKey: String? = nil) {
        self.titleKey = titleKey
        self.noteKey = noteKey
        self.chips = chips
        self.footnoteKey = footnoteKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string(titleKey))
                if let noteKey {
                    AraSettingsNote(L10n.string(noteKey))
                }
            }
            AraFlowRow(spacing: 5) {
                ForEach(chips) { chip in
                    AraSettingsChip(title: chip.title, isOn: chip.isOn)
                }
            }
            if let footnoteKey {
                AraSettingsNote(L10n.string(footnoteKey))
            }
        }
        .padding(.vertical, 2)
    }
}

/// One chip of an `AraChipRow`: filled when on, outlined when off; a click turns it over.
struct AraSettingsChip: View {
    let title: String
    let isOn: Binding<Bool>

    var body: some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                if isOn.wrappedValue {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .foregroundStyle(isOn.wrappedValue ? AraPalette.onAccent : AraPalette.ink)
            .background {
                if isOn.wrappedValue {
                    Capsule().fill(AraPalette.ink)
                } else {
                    Capsule().strokeBorder(AraPalette.line, lineWidth: AraTheme.outline)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(AraPressStyle(depth: 0.95))
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
        .animation(AraTheme.hover, value: isOn.wrappedValue)
    }
}

/// Lays its children out left to right and wraps them onto further lines.
public struct AraFlowRow: Layout {
    let spacing: CGFloat

    public init(spacing: CGFloat) {
        self.spacing = spacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
