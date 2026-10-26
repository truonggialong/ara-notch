import Testing
@testable import NotchCore

private let a = PageDescriptor(id: "a", titleKey: "page.a", symbolName: "a.circle")
private let b = PageDescriptor(id: "b", titleKey: "page.b", symbolName: "b.circle")
private let c = PageDescriptor(id: "c", titleKey: "page.c", symbolName: "c.circle")

private func registry(_ pages: PageDescriptor...) -> PageRegistry {
    var registry = PageRegistry()
    pages.forEach { registry.register($0) }
    return registry
}

@Suite struct PageRegistryTests {
    @Test func emptyRegistryHasNoSelection() {
        let registry = PageRegistry()
        #expect(registry.pages.isEmpty)
        #expect(registry.selectedID == nil)
    }

    @Test func firstRegisteredPageIsSelected() {
        let registry = registry(a, b)
        #expect(registry.selectedID == "a")
        #expect(registry.pages.map(\.id) == ["a", "b"])
    }

    @Test func duplicateIDIsIgnored() {
        var registry = registry(a)
        registry.register(PageDescriptor(id: "a", titleKey: "page.other", symbolName: "x"))
        #expect(registry.pages == [a])
    }

    @Test func selectChangesSelection() {
        var registry = registry(a, b)
        registry.select("b")
        #expect(registry.selectedID == "b")
    }

    @Test func selectUnknownIDIsIgnored() {
        var registry = registry(a, b)
        registry.select("zzz")
        #expect(registry.selectedID == "a")
    }

    @Test func selectNextWrapsAround() {
        var registry = registry(a, b, c)
        registry.selectNext()
        #expect(registry.selectedID == "b")
        registry.select("c")
        registry.selectNext()
        #expect(registry.selectedID == "a")
    }

    @Test func selectPreviousWrapsAround() {
        var registry = registry(a, b, c)
        registry.selectPrevious()
        #expect(registry.selectedID == "c")
        registry.selectPrevious()
        #expect(registry.selectedID == "b")
    }

    @Test func navigationIsNoOpWithFewerThanTwoPages() {
        var empty = PageRegistry()
        empty.selectNext()
        empty.selectPrevious()
        #expect(empty.selectedID == nil)

        var single = registry(a)
        single.selectNext()
        single.selectPrevious()
        #expect(single.selectedID == "a")
    }
}

@Suite struct PageLayoutTests {
    private func registry(_ ids: String...) -> PageRegistry {
        var registry = PageRegistry()
        for id in ids {
            registry.register(PageDescriptor(id: id, titleKey: "page.\(id)", symbolName: "circle"))
        }
        return registry
    }

    @Test func withoutALayoutPagesShowInRegistrationOrder() {
        let registry = registry("a", "b", "c")
        #expect(registry.pages.map(\.id) == ["a", "b", "c"])
        #expect(registry.allPages.map(\.id) == ["a", "b", "c"])
        #expect(registry.hiddenIDs.isEmpty)
    }

    @Test func aStoredOrderIsFollowedAndUnknownIdsAreIgnored() {
        var registry = registry("a", "b", "c")
        registry.applyLayout(order: ["c", "zzz", "a"], hidden: [])
        // Pages the order does not mention keep their place after the ordered ones.
        #expect(registry.pages.map(\.id) == ["c", "a", "b"])
        #expect(registry.order == ["c", "a", "b"])
    }

    @Test func hiddenPagesAreLeftOutButStayKnown() {
        var registry = registry("a", "b", "c")
        registry.applyLayout(order: [], hidden: ["b", "zzz"])
        #expect(registry.pages.map(\.id) == ["a", "c"])
        #expect(registry.allPages.map(\.id) == ["a", "b", "c"])
        #expect(registry.hiddenIDs == ["b"])
    }

    @Test func hidingTheSelectedPageSelectsTheFirstVisibleOne() {
        var registry = registry("a", "b", "c")
        registry.select("b")
        registry.setHidden(true, id: "b")
        #expect(registry.selectedID == "a")
        registry.select("b")
        #expect(registry.selectedID == "a")
    }

    @Test func theLastVisiblePageCannotBeHidden() {
        var registry = registry("a", "b")
        registry.setHidden(true, id: "a")
        registry.setHidden(true, id: "b")
        #expect(registry.pages.map(\.id) == ["b"])
        registry.applyLayout(order: [], hidden: ["a", "b"])
        #expect(registry.pages.map(\.id) == ["a"])
    }

    @Test func pagesMoveUpAndDownWithinTheFullList() {
        var registry = registry("a", "b", "c")
        registry.move(id: "c", by: -1)
        #expect(registry.order == ["a", "c", "b"])
        registry.move(id: "a", by: 1)
        #expect(registry.order == ["c", "a", "b"])
        registry.move(id: "c", by: -1)
        registry.move(id: "b", by: 1)
        registry.move(id: "zzz", by: 1)
        #expect(registry.order == ["c", "a", "b"])
    }

    @Test func steppingSkipsHiddenPages() {
        var registry = registry("a", "b", "c")
        registry.setHidden(true, id: "b")
        registry.selectNext()
        #expect(registry.selectedID == "c")
        registry.selectNext()
        #expect(registry.selectedID == "a")
    }

    @Test func aPageRegisteredAfterTheLayoutStillObeysIt() {
        var registry = PageRegistry()
        registry.applyLayout(order: ["b", "a"], hidden: ["c"])
        for id in ["a", "b", "c"] {
            registry.register(PageDescriptor(id: id, titleKey: id, symbolName: "circle"))
        }
        #expect(registry.pages.map(\.id) == ["b", "a"])
        #expect(registry.selectedID == "b")
    }

    @Test func aSavedOrderWithoutTheLeadingPageGetsItInFront() {
        #expect(PageRegistry.order(["media", "clipboard"], leading: "overview") == ["overview", "media", "clipboard"])
        // No order was ever chosen: pages stay in the order the app adds them.
        #expect(PageRegistry.order([], leading: "overview") == [])
        // The user already placed it.
        #expect(PageRegistry.order(["clipboard", "overview"], leading: "overview") == ["clipboard", "overview"])
        #expect(PageRegistry.order(["media"], leading: nil) == ["media"])
    }
}
