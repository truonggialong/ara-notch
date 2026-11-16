import NotchShell
import SwiftUI

/// The tools page and the overview's tools widget: everything that otherwise takes a shortcut
/// or the menu bar. The app says which tools there are and what each one starts.
@MainActor
public final class ToolsController {
    let tools: [NotchTool]
    /// The tools the small and wide widget show, in the order given.
    let quickTools: [NotchTool]
    /// The tools that are on now; the app says which, such as keeping the Mac awake.
    public let states = ToolStates()

    public init(tools: [NotchTool], quickToolIDs: [String]) {
        self.tools = tools
        quickTools = quickToolIDs.compactMap { id in tools.first { $0.id == id } }
    }

    public func makePage() -> NotchPage {
        let tools = tools
        let states = states
        var page = NotchPage(id: "tools", titleKey: "page.tools.title", symbolName: "wrench.and.screwdriver") {
            ToolsPage(tools: tools, states: states)
        }
        // Two rows of round buttons.
        page.sheetSize = CGSize(width: 480, height: 200)
        return page
    }

    /// Shows a tool as on (coloured, with a number in place of its icon), or with nil as off.
    public func setState(_ state: NotchToolState?, forTool id: String) {
        states.states[id] = state
    }

    public func makeOverviewTile() -> AnyView {
        AnyView(ToolsWidget(quickTools: quickTools, allTools: tools))
    }
}
