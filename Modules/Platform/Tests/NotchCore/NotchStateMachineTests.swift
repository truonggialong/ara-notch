import Testing
@testable import NotchCore

private typealias Event = NotchStateMachine.Event
private typealias Effect = NotchStateMachine.Effect
private typealias State = NotchStateMachine.State

private let movedIn = Event.pointerMoved(inside: true)
private let movedOut = Event.pointerMoved(inside: false)
private let clickIn = Event.clicked(inside: true)
private let clickOut = Event.clicked(inside: false)

/// Feeds the events in order and returns the final state plus the effects of each event.
private func run(_ events: [Event], openOnHover: Bool = true) -> (state: State, effects: [[Effect]]) {
    var machine = NotchStateMachine(openOnHover: openOnHover)
    let effects = events.map { machine.handle($0) }
    return (machine.state, effects)
}

@Suite struct NotchStateMachineTransitionTests {
    @Test(arguments: [
        ([movedIn], State.hoverPending, [Effect.scheduleHoverTimer]),
        ([clickIn], .open, [.didOpen]),
        ([movedIn, movedOut], .closed, [.cancelHoverTimer]),
        ([movedIn, .hoverDelayElapsed], .open, [.didOpen]),
        ([movedIn, clickIn], .open, [.cancelHoverTimer, .didOpen]),
        ([clickIn, movedOut], .closePending, [.scheduleCloseTimer]),
        ([clickIn, clickOut], .closed, [.didClose]),
        ([clickIn, movedOut, movedIn], .open, [.cancelCloseTimer]),
        ([clickIn, movedOut, .closeDelayElapsed], .closed, [.didClose]),
        ([clickIn, movedOut, clickOut], .closed, [.cancelCloseTimer, .didClose]),
        ([clickIn, .forceClose], .closed, [.didClose]),
        ([clickIn, movedOut, .forceClose], .closed, [.cancelCloseTimer, .didClose]),
        ([movedIn, .forceClose], .closed, [.cancelHoverTimer]),
        ([.forceOpen], .open, [.didOpen]),
        ([movedIn, .forceOpen], .open, [.cancelHoverTimer, .didOpen]),
        ([clickIn, movedOut, .forceOpen], .open, [.cancelCloseTimer]),
    ] as [([Event], State, [Effect])])
    func transition(events: [NotchStateMachine.Event], finalState: NotchStateMachine.State, lastEffects: [NotchStateMachine.Effect]) {
        let result = run(events)
        #expect(result.state == finalState)
        #expect(result.effects.last == lastEffects)
    }

    @Test func hoverIgnoredWhenDisabled() {
        let result = run([movedIn], openOnHover: false)
        #expect(result.state == .closed)
        #expect(result.effects == [[]])
    }

    @Test func clickOpensEvenWhenHoverDisabled() {
        let result = run([clickIn], openOnHover: false)
        #expect(result.state == .open)
        #expect(result.effects == [[.didOpen]])
    }
}

@Suite struct NotchStateMachineIgnoredEventTests {
    @Test(arguments: [
        ([Event.hoverDelayElapsed], State.closed),
        ([clickIn, .hoverDelayElapsed], .open),
        ([clickIn, .closeDelayElapsed], .open),
        ([clickIn, clickIn], .open),
        ([clickOut], .closed),
        ([movedIn, movedIn], .hoverPending),
        ([clickIn, movedOut, movedOut], .closePending),
        ([clickIn, .forceOpen], .open),
        ([.forceClose], .closed),
    ] as [([Event], State)])
    func lastEventIsIgnored(events: [NotchStateMachine.Event], unchangedState: NotchStateMachine.State) {
        let result = run(events)
        #expect(result.state == unchangedState)
        #expect(result.effects.last == [])
    }
}

@Suite struct NotchStateMachineBehaviorTests {
    @Test func rapidInOutNeverLeavesTwoHoverTimers() {
        let result = run([movedIn, movedOut, movedIn, movedOut, movedIn])
        #expect(result.state == .hoverPending)
        #expect(result.effects == [
            [.scheduleHoverTimer], [.cancelHoverTimer], [.scheduleHoverTimer],
            [.cancelHoverTimer], [.scheduleHoverTimer],
        ])
    }

    @Test func isPresentedReflectsOpenAndClosePending() {
        var machine = NotchStateMachine()
        #expect(!machine.isPresented)
        _ = machine.handle(movedIn)
        #expect(machine.state == .hoverPending)
        #expect(!machine.isPresented)
        _ = machine.handle(.hoverDelayElapsed)
        #expect(machine.state == .open)
        #expect(machine.isPresented)
        _ = machine.handle(movedOut)
        #expect(machine.state == .closePending)
        #expect(machine.isPresented)
    }
}

@Suite struct NotchStateMachineHoldOpenTests {
    @Test func forceOpenStaysOpenWhilePointerIsElsewhere() {
        let result = run([.forceOpen, movedOut, movedOut])
        #expect(result.state == .open)
        #expect(result.effects == [[.didOpen], [], []])
    }

    @Test func holdEndsOncePointerEntersThePanel() {
        let result = run([.forceOpen, movedOut, movedIn, movedOut])
        #expect(result.state == .closePending)
        #expect(result.effects.last == [.scheduleCloseTimer])
    }

    @Test func clickOutsideClosesAHeldPanel() {
        let result = run([.forceOpen, clickOut])
        #expect(result.state == .closed)
        #expect(result.effects.last == [.didClose])
    }

    @Test func holdDoesNotSurviveClosing() {
        let result = run([.forceOpen, .forceClose, clickIn, movedOut])
        #expect(result.state == .closePending)
    }

    @Test func forceOpenDuringCloseDelayHoldsThePanel() {
        let result = run([clickIn, movedOut, .forceOpen, movedOut])
        #expect(result.state == .open)
        #expect(result.effects.last == [])
    }

    @Test func openingByClickDoesNotHold() {
        let result = run([clickIn, movedOut])
        #expect(result.state == .closePending)
    }
}

@Suite struct NotchStateMachineMenuTests {
    /// Opens the panel, puts a menu up from it, then feeds the events.
    private func runWithMenu(_ events: [Event]) -> NotchStateMachine {
        var machine = NotchStateMachine()
        _ = machine.handle(clickIn)
        machine.isMenuTracking = true
        for event in events {
            _ = machine.handle(event)
        }
        return machine
    }

    @Test func thePointerOnAMenuDoesNotCloseThePanelUnderIt() {
        #expect(runWithMenu([movedOut]).state == .open)
    }

    @Test func choosingAMenuItemOutsideThePanelDoesNotCloseIt() {
        #expect(runWithMenu([movedOut, clickOut]).state == .open)
    }

    @Test func onceTheMenuIsGoneThePanelClosesAsUsual() {
        var machine = runWithMenu([movedOut])
        machine.isMenuTracking = false
        #expect(machine.handle(movedOut) == [.scheduleCloseTimer])
        #expect(machine.handle(.closeDelayElapsed) == [.didClose])
    }

    @Test func aMenuDoesNotStopAForcedClose() {
        #expect(runWithMenu([.forceClose]).state == .closed)
    }

    @Test func aHeldPanelWaitsForThePointerToComeBack() {
        // A menu's item was chosen far from the panel while something was being typed in it.
        var machine = runWithMenu([movedOut])
        machine.isMenuTracking = false
        machine.hold()
        #expect(machine.handle(movedOut) == [])
        #expect(machine.state == .open)
        #expect(machine.handle(movedIn) == [])
        #expect(machine.handle(movedOut) == [.scheduleCloseTimer])
    }

    @Test func aClickElsewhereClosesAHeldPanel() {
        var machine = runWithMenu([movedOut])
        machine.isMenuTracking = false
        machine.hold()
        #expect(machine.handle(clickOut) == [.didClose])
    }

    @Test func holdingAClosedPanelDoesNothing() {
        var machine = NotchStateMachine()
        machine.hold()
        _ = machine.handle(clickIn)
        #expect(machine.handle(movedOut) == [.scheduleCloseTimer])
    }
}

@Suite struct NotchStateMachineStayOpenTests {
    private func opened() -> NotchStateMachine {
        var machine = NotchStateMachine()
        _ = machine.handle(clickIn)
        return machine
    }

    @Test func aPinnedPanelStaysWhenThePointerLeavesOrClicksElsewhere() {
        var machine = opened()
        machine.isPinned = true
        #expect(machine.handle(movedOut) == [])
        #expect(machine.handle(clickOut) == [])
        #expect(machine.state == .open)
    }

    @Test func aPinnedPanelStillClosesWhenToldTo() {
        var machine = opened()
        machine.isPinned = true
        #expect(machine.handle(.forceClose) == [.didClose])
    }

    @Test func unpinningLetsThePointerDecideAgain() {
        var machine = opened()
        machine.isPinned = true
        _ = machine.handle(movedOut)
        machine.isPinned = false
        #expect(machine.handle(movedOut) == [.scheduleCloseTimer])
    }

    @Test func pinningWhileThePanelIsAboutToCloseKeepsIt() {
        var machine = opened()
        _ = machine.handle(movedOut)
        machine.isPinned = true
        #expect(machine.handle(.closeDelayElapsed) == [])
        #expect(machine.state == .closePending)
        #expect(machine.handle(movedIn) == [.cancelCloseTimer])
    }

    @Test func aPanelKeptOpenByItsPageStaysWhenThePointerLeavesOrClicksElsewhere() {
        // A day and a time are being chosen: the panel stays until the page's own button ends it.
        var machine = opened()
        machine.isKeptOpen = true
        #expect(machine.handle(movedOut) == [])
        #expect(machine.handle(clickOut) == [])
        #expect(machine.state == .open)
        // Escape, or anything else that tells it to close, still does.
        #expect(machine.handle(.forceClose) == [.didClose])
    }

    @Test func whenThePageLetsGoThePointerDecidesAgain() {
        var machine = opened()
        machine.isKeptOpen = true
        _ = machine.handle(movedOut)
        machine.isKeptOpen = false
        #expect(machine.handle(movedOut) == [.scheduleCloseTimer])
    }

    @Test func aPageThatKeepsThePanelWhileItIsAboutToCloseKeepsIt() {
        var machine = opened()
        _ = machine.handle(movedOut)
        machine.isKeptOpen = true
        #expect(machine.handle(.closeDelayElapsed) == [])
        #expect(machine.state == .closePending)
    }

    @Test func aPageBeingEditedStaysWhenThePointerLeavesButAClickElsewhereCloses() {
        // The overview's tiles are being arranged: the pointer wanders off while dragging,
        // but a click elsewhere means the user is done.
        var machine = opened()
        machine.isBeingEdited = true
        #expect(machine.handle(movedOut) == [])
        #expect(machine.state == .open)
        #expect(machine.handle(clickOut) == [.didClose])
    }

    @Test func aPageBeingEditedWhileAboutToCloseIsNotClosedByTheDelay() {
        var machine = opened()
        _ = machine.handle(movedOut)
        machine.isBeingEdited = true
        #expect(machine.handle(.closeDelayElapsed) == [])
    }

    @Test func whileSomethingIsBeingTypedThePointerLeavingDoesNotClose() {
        var machine = opened()
        machine.isTyping = true
        #expect(machine.handle(movedOut) == [])
        #expect(machine.state == .open)
    }

    @Test func aClickElsewhereClosesEvenWhileTyping() {
        var machine = opened()
        machine.isTyping = true
        #expect(machine.handle(clickOut) == [.didClose])
    }

    @Test func onceTypingIsOverThePointerDecidesAgain() {
        var machine = opened()
        machine.isTyping = true
        _ = machine.handle(movedOut)
        machine.isTyping = false
        #expect(machine.handle(movedOut) == [.scheduleCloseTimer])
    }
}
