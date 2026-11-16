import NotchShell
import SwiftUI

/// The tools page: everything that otherwise takes a shortcut or the menu bar, as buttons
/// large enough to hit without looking twice.
struct ToolsPage: View {
    @Environment(\.araScale) private var ui
    let tools: [NotchTool]

    var body: some View {
        // Rows across the page while they fit, else sideways (`AraRail`).
        AraRail(tools, itemSize: CGSize(width: 104, height: 66)) { tool in
            ToolTile(tool: tool)
        }
    }
}

private struct ToolTile: View {
    @Environment(\.araScale) private var ui
    let tool: NotchTool
    @StateObject private var hover = AraHover()

    var body: some View {
        Button(action: tool.action) {
            VStack(spacing: 6 * ui) {
                tool.icon.image
                    .font(.system(size: 17 * ui, weight: .medium))
                    .foregroundStyle(AraPalette.tint(tool.hue).line)
                Text(L10n.string("tools.\(tool.id)"))
                    .font(.system(size: 11 * ui, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66 * ui)
            .contentShape(Rectangle())
        }
        .buttonStyle(AraPressStyle(depth: 0.96))
        .araCard(radius: 14, level: hover.isHovered ? .raised : .plate)
        .onHover { hover.isHovered = $0 }
        .accessibilityLabel(L10n.string("tools.\(tool.id)"))
    }
}
