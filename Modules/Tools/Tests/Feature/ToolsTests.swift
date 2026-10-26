import NotchShell
import Testing
@testable import ToolsFeature

@MainActor
@Suite struct ToolsTests {
    @Test func eachToolTakesItsLookFromItsName() {
        let translate = NotchTool(id: "translate") {}
        #expect(translate.icon == .translate)
        #expect(translate.hue == .sky)
        let capture = NotchTool(id: "capture") {}
        #expect(capture.icon == .captureRegion)
        #expect(capture.hue == .peach)
    }

    @Test func aToolWithNoLookOfItsOwnGetsTheGridInPeach() {
        let unknown = NotchTool(id: "weather") {}
        #expect(unknown.icon == .grid)
        #expect(unknown.hue == .peach)
    }

    @Test func theQuickToolsFollowTheChosenNamesAndSkipUnknownOnes() {
        let tools = ["capture", "text", "color", "translate", "panel"].map { NotchTool(id: $0) {} }
        let controller = ToolsController(tools: tools, quickToolIDs: ["translate", "missing", "capture"])
        #expect(controller.quickTools.map(\.id) == ["translate", "capture"])
    }
}
