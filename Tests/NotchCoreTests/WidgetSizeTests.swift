import Testing
@testable import NotchCore

@Suite struct WidgetSizeTests {
    @Test func sizesCycleSmallWideLarge() {
        #expect(WidgetSize.small.next == .wide)
        #expect(WidgetSize.wide.next == .large)
        #expect(WidgetSize.large.next == .small)
    }

    @Test func storedNamesStayTheSame() {
        #expect(WidgetSize.allCases.map(\.rawValue) == ["small", "wide", "large"])
    }
}
