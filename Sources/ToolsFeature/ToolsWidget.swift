import NotchShell
import SwiftUI

/// The tools as a widget of the overview: round buttons in each tool's colour, named under
/// or beside them. Small: the four used most, in two rows, with short names. Wide: those four
/// in a row with their full names. Large: every tool, in two rows.
struct ToolsWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    let quickTools: [NotchTool]
    let allTools: [NotchTool]

    var body: some View {
        AraWidget(name: L10n.string("widget.tools.label"), hue: nil) {
            switch size {
            case .small:
                VStack(alignment: .leading, spacing: 4 * ui) {
                    ForEach(Array(stride(from: 0, to: quickTools.count, by: 2)), id: \.self) { first in
                        HStack(spacing: 4 * ui) {
                            ForEach(quickTools[first..<min(first + 2, quickTools.count)]) { tool in
                                HStack(spacing: 4 * ui) {
                                    button(tool, diameter: 22)
                                    Text(L10n.string("widget.tool.\(tool.id)"))
                                        .font(.system(size: 10.5 * ui, weight: .semibold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            case .wide:
                row(quickTools, diameter: 24)
                    .frame(maxHeight: .infinity)
            case .large:
                VStack(spacing: 6 * ui) {
                    row(Array(allTools.prefix(4)), diameter: 30)
                    row(Array(allTools.dropFirst(4).prefix(4)), diameter: 30)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func row(_ tools: [NotchTool], diameter: CGFloat) -> some View {
        HStack(spacing: 4 * ui) {
            ForEach(tools) { tool in
                VStack(spacing: 3 * ui) {
                    button(tool, diameter: diameter)
                    // Two lines at most, so the full name shows.
                    Text(L10n.string("tools.\(tool.id)"))
                        .font(.system(size: 10.5 * ui, weight: .medium))
                        .foregroundStyle(AraPalette.widgetSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                        .frame(height: 26 * ui, alignment: .top)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func button(_ tool: NotchTool, diameter: CGFloat) -> some View {
        AraRoundButton(
            icon: tool.icon, label: L10n.string("tools.\(tool.id)"), isPrimary: true, hue: tool.hue, diameter: diameter,
            action: tool.action)
    }
}
