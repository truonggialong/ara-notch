import NotchShell
import SwiftUI

/// The tools page and the overview's tools widget: everything that otherwise takes a shortcut
/// or the menu bar. The app says which tools there are and what each one starts.
@MainActor
public final class ToolsController {
    let tools: [NotchTool]
    /// The tools the small and wide widget show, in the order given.
    let quickTools: [NotchTool]

    public init(tools: [NotchTool], quickToolIDs: [String]) {
        self.tools = tools
        quickTools = quickToolIDs.compactMap { id in tools.first { $0.id == id } }
    }

    public func makePage() -> NotchPage {
        let tools = tools
        return NotchPage(id: "tools", titleKey: "page.tools.title", symbolName: "wrench.and.screwdriver") {
            ToolsPage(tools: tools)
        }
    }

    public func makeOverviewTile() -> AnyView {
        AnyView(ToolsWidget(quickTools: quickTools, allTools: tools))
    }
}
