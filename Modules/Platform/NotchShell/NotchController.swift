import AppKit
import Combine
import NotchCore
import SwiftUI

/// Owns the notch window and connects pointer input to the state machine.
@MainActor
public final class NotchController {
    /// Invoked when the settings button in the notch header is pressed.
    public var onOpenSettings: (() -> Void)? {
        didSet { viewModel.onOpenSettings = onOpenSettings }
    }

    /// Geometry of the display the notch is currently shown on; nil when there is no display.
    public private(set) var geometry: NotchGeometry?

    private static let safetyNetInterval: TimeInterval = 1.0 / 15

    public let settings: ShellSettings
    private let viewModel = NotchViewModel()
    private let pointer = PointerMonitor()
    private var stateMachine: NotchStateMachine
    private var swipe = SwipeAccumulator()
    /// Frame of the display the notch is on.
    private var currentScreenFrame: CGRect?
    private var verticalSwipe = VerticalSwipeDetector(threshold: SwipeSensitivity.medium.threshold)
    private var panel: NotchPanel?
    /// The closed notch as another display shows it, when the notch is on every display: a
    /// window and what it is drawn from. Only the notch under the pointer answers; these are
    /// to be looked at, and one is put away while its display has the notch that answers.
    private struct Mirror {
        let panel: NotchPanel
        let model: NotchViewModel
    }
    private var mirrors: [CGDirectDisplayID: Mirror] = [:]
    /// While something shows on the closed notch, a window just as large as it takes the
    /// clicks on it, which the notch's own window lets through to whatever is underneath.
    private var clickCatcher: NotchClickCatcher?
    /// The displays an app is full screen on, as last looked.
    private var fullScreenDisplays: Set<CGDirectDisplayID> = []
    private var hoverTimer: Timer?
    private var closeTimer: Timer?
    private var safetyNetTimer: Timer?
    /// How many menus opened from the open panel are on screen.
    private var menuDepth = 0
    /// The page to show on the next open, because the click that opens was on its activity.
    private var pageForNextOpen: String?
    private var keyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var isStarted = false
    private var activityQueue = LiveActivityQueue()
    private var activityContents: [String: NotchLiveActivity] = [:]
    /// The taller sheets some pages ask for, by page.
    private var pageSheetHeights: [String: CGFloat] = [:]
    /// The pages that have asked the notch to stay open until they say otherwise.
    private var pagesKeepingOpen: Set<String> = []
    /// The pages being edited: the pointer leaving does not close the notch while they show.
    private var pagesBeingEdited: Set<String> = []
    private var activityTimer: Timer?

    /// Emits whether the notch is open: the current value first, then every change.
    public var isOpenPublisher: AnyPublisher<Bool, Never> {
        viewModel.$isOpen.removeDuplicates().eraseToAnyPublisher()
    }

    /// True while the notch holds keyboard focus (for example after its search field was clicked).
    public var isKeyWindow: Bool {
        panel?.isKeyWindow ?? false
    }

    public var selectedPageID: String? {
        viewModel.registry.selectedID
    }

    /// What of the open notch holds no page content, in points of the sheet a page asks for:
    /// the tab row, which keeps the hardware notch's height at every size, and the page's
    /// margins.
    public var pageChrome: CGFloat {
        viewModel.closedSize.height / viewModel.scale + 2 * NotchRootView.contentPadding
    }

    /// Emits the page shown: the current one first, then every change.
    public var selectedPagePublisher: AnyPublisher<String?, Never> {
        viewModel.$registry.map(\.selectedID).removeDuplicates().eraseToAnyPublisher()
    }

    /// Whether this window is one of the notch's own windows.
    public func owns(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return window === panel || window === clickCatcher || mirrors.values.contains { $0.panel === window }
    }

    /// The app's global shortcuts; features hang their own actions on it.
    public let shortcuts: ShortcutCenter
    /// The user put the notch away with the shortcut; it comes back with the same shortcut.
    public private(set) var isHiddenByUser = false

    /// `leadingPageID` is the page put in front of a page order saved before it existed.
    public init(settings: ShellSettings, shortcuts: ShortcutCenter? = nil, leadingPageID: String? = nil) {
        self.settings = settings
        self.shortcuts = shortcuts ?? ShortcutCenter(store: ShortcutStore(defaults: .standard))
        stateMachine = NotchStateMachine(openOnHover: settings.openOnHover)
        apply(settings.notchSize)
        // Applied before any page is registered, so pages fall into place as they arrive.
        viewModel.registry.applyLayout(
            order: PageRegistry.order(settings.pageOrder, leading: leadingPageID), hidden: settings.hiddenPages)
    }

    /// Called when the notch opens because files were dragged onto it.
    public var onFileDrag: (() -> Void)?

    public func register(page: NotchPage) {
        guard viewModel.pages[page.id] == nil else { return }
        viewModel.pages[page.id] = page
        viewModel.registry.register(page.descriptor)
    }

    // MARK: - Page layout

    /// Every registered page in tab order, hidden ones included.
    public var allPages: [PageDescriptor] {
        viewModel.registry.allPages
    }

    public func isPageHidden(id: String) -> Bool {
        viewModel.registry.hiddenIDs.contains(id)
    }

    /// Hides or shows a page's tab and remembers it. The last visible page cannot be hidden.
    public func setPageHidden(_ isHidden: Bool, id: String) {
        viewModel.registry.setHidden(isHidden, id: id)
        saveLayout()
    }

    /// Moves a page's tab one place left (-1) or right (1) and remembers it.
    public func movePage(id: String, by offset: Int) {
        viewModel.registry.move(id: id, by: offset)
        saveLayout()
    }

    private func saveLayout() {
        settings.pageOrder = viewModel.registry.order
        settings.hiddenPages = viewModel.registry.hiddenIDs.sorted()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        settings.$hidesFromCapture
            .sink { [weak self] hides in
                self?.panel?.sharingType = hides ? .none : .readOnly
                self?.mirrors.values.forEach { $0.panel.sharingType = hides ? .none : .readOnly }
            }
            .store(in: &cancellables)
        settings.$displayMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layoutForCurrentScreen() }
            .store(in: &cancellables)
        settings.$notchSize
            .receive(on: RunLoop.main)
            .sink { [weak self] size in
                guard let self, self.viewModel.scale != size.scale else { return }
                self.send(.forceClose)
                self.apply(size)
                self.layoutForCurrentScreen()
            }
            .store(in: &cancellables)
        settings.$pillStyle
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.send(.forceClose)
                self?.layoutForCurrentScreen()
            }
            .store(in: &cancellables)

        settings.$openOnHover
            .sink { [weak self] isEnabled in self?.openOnHoverChanged(to: isEnabled) }
            .store(in: &cancellables)
        settings.$hapticsEnabled
            .sink { AraHaptics.isEnabled = $0 }
            .store(in: &cancellables)
        settings.$hidesInFullScreen
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyFullScreenHiding() }
            .store(in: &cancellables)
        // An app goes full screen in a Space of its own; coming back to a desktop, or to
        // another app, is the moment to look again.
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.checkFullScreen()
                    // The app is told before its windows are all on screen: look again shortly.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.checkFullScreen() }
                }
                .store(in: &cancellables)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // A word still being composed by the input method gets its keys first.
            guard let self, !event.isForInputMethod, self.handleKey(event) else { return event }
            return nil
        }
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &cancellables)
        // Delivered as they happen: a menu runs its own event loop, which a hop to the main queue would wait out.
        NotificationCenter.default
            .publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.menuTracking(began: true) }
            .store(in: &cancellables)
        NotificationCenter.default
            .publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in self?.menuTracking(began: false) }
            .store(in: &cancellables)

        pointer.onMove = { [weak self] point in self?.pointerMoved(to: point) }
        pointer.onClick = { [weak self] point in self?.clicked(at: point) }
        pointer.onScroll = { [weak self] event in self?.scrolled(event) }
        viewModel.onTogglePin = { [weak self] in self?.togglePin() }
        // Another page on show may want another height.
        viewModel.$registry
            .map(\.selectedID)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshOpenSize()
                self?.refreshKeptOpen()
            }
            .store(in: &cancellables)
        pointer.rewriteScroll = { [weak self] event in self?.sidewaysScroll(for: event) }
        pointer.onFileDrag = { [weak self] point in self?.filesDragged(to: point) }
        pointer.start()
        shortcuts.setHandler(.openNotch) { [weak self] in self?.toggleOpen() }
        shortcuts.setHandler(.hideNotch) { [weak self] in self?.toggleHidden() }

        layoutForCurrentScreen()
    }

    public func open() {
        send(.forceOpen)
    }

    /// Opens the closed notch, closes the open one. Opened this way, from the keyboard, the
    /// notch takes the keys, so it can be used without the pointer.
    public func toggleOpen() {
        guard !isHiddenByUser else { return }
        if stateMachine.isPresented {
            send(.forceClose)
        } else {
            send(.forceOpen)
            takeKeyboard()
        }
    }

    /// Puts the caret in the text field a page has just shown, such as a new reminder's, so
    /// it can be typed in without a click.
    public func focusTextField() {
        guard stateMachine.isPresented else { return }
        takeKeyboard()
    }

    /// Makes the notch the key window and puts the caret in the page's text field, if it has one.
    private func takeKeyboard() {
        guard let panel else { return }
        panel.makeKey()
        focusTextField(attemptsLeft: 6)
    }

    /// A field that has only just been asked for is not on screen yet, so this looks again a
    /// few times, a moment apart, before giving up.
    private func focusTextField(attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let panel = self.panel, panel.isKeyWindow, self.stateMachine.isPresented,
                  let content = panel.contentView
            else { return }
            if let field = Self.firstTextField(in: content) {
                if panel.firstResponder !== field.currentEditor() {
                    panel.makeFirstResponder(field)
                }
            } else if attemptsLeft > 1 {
                self.focusTextField(attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.isEditable { return field }
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }

    /// Keys while the notch has the keyboard: Tab and Shift-Tab change page, Escape closes,
    /// and the rest go to the page that is showing.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard stateMachine.isPresented, let panel, event.window === panel, panel.isKeyWindow else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.isDisjoint(with: [.command, .control, .option]),
              let key = NotchKey(keyCode: event.keyCode, isShiftDown: flags.contains(.shift))
        else { return false }
        let isTyping = panel.firstResponder is NSTextView
        if let id = viewModel.registry.selectedID, viewModel.pages[id]?.keyHandler?(key, isTyping) == true {
            return true
        }
        guard !isTyping || key.worksWhileTyping else { return false }
        switch key {
        case .nextPage:
            viewModel.registry.selectNext()
            takeKeyboard()
        case .previousPage:
            viewModel.registry.selectPrevious()
            takeKeyboard()
        case .escape:
            send(.forceClose)
        default:
            return false
        }
        return true
    }

    /// Takes the notch off the screen entirely, or brings it back. While it is away it does
    /// not react to the pointer, so the menu bar beside it is free.
    public func toggleHidden() {
        isHiddenByUser.toggle()
        if isHiddenByUser {
            send(.forceClose)
            panel?.orderOut(nil)
            layoutMirrors()
            refreshClickCatcher()
        } else {
            layoutForCurrentScreen()
        }
    }

    /// Closes the panel after something was done from it. A pinned panel stays: that is
    /// what it was pinned for.
    public func close() {
        guard !stateMachine.staysOpen else { return }
        send(.forceClose)
    }

    /// Pins the open panel, or lets the pointer decide again.
    private func togglePin() {
        guard stateMachine.isPresented else { return }
        stateMachine.isPinned.toggle()
        viewModel.isPinned = stateMachine.staysOpen
        AraHaptics.play(.tap)
        if !stateMachine.staysOpen {
            pointerMoved(to: NSEvent.mouseLocation)
        }
    }

    /// Lets a page keep the notch open while something on it is under way that ends with
    /// a button of its own, such as choosing a day and a time: until the page lets go, the
    /// notch stays as if pinned, and the pin shows it. Only while that page is the one shown.
    public func setKeepsOpen(_ keeps: Bool, forPage id: String) {
        if keeps {
            pagesKeepingOpen.insert(id)
        } else {
            pagesKeepingOpen.remove(id)
        }
        refreshKeptOpen()
    }

    /// Lets a page say it is being edited, as the overview while its tiles are arranged: the
    /// notch stays while the pointer is away, and a click elsewhere still closes it. Only
    /// while that page is the one shown.
    public func setBeingEdited(_ isEdited: Bool, forPage id: String) {
        if isEdited {
            pagesBeingEdited.insert(id)
        } else {
            pagesBeingEdited.remove(id)
        }
        refreshKeptOpen()
    }

    private func refreshKeptOpen() {
        let edited = viewModel.registry.selectedID.map(pagesBeingEdited.contains) ?? false
        if stateMachine.isBeingEdited != edited {
            stateMachine.isBeingEdited = edited
            if !edited {
                pointerMoved(to: NSEvent.mouseLocation)
            }
        }
        let keeps = viewModel.registry.selectedID.map(pagesKeepingOpen.contains) ?? false
        guard stateMachine.isKeptOpen != keeps else { return }
        stateMachine.isKeptOpen = keeps
        viewModel.isPinned = stateMachine.staysOpen
        if !stateMachine.staysOpen {
            // The pointer decides again, from where it is now.
            pointerMoved(to: NSEvent.mouseLocation)
        }
    }

    /// The pointer came onto the closed notch or left it. The notch swells to answer; when it
    /// opens only on a click, the touch is also felt, since nothing else will follow.
    private func touchChanged(to isTouched: Bool) {
        guard viewModel.isTouched != isTouched else { return }
        viewModel.isTouched = isTouched
        viewModel.allowsPeek = !settings.openOnHover
        if isTouched, !settings.openOnHover {
            AraHaptics.play(.tap)
        }
    }

    /// Text is being written in the panel: its field holds the keyboard and is not empty.
    private var isTypingInPanel: Bool {
        guard let panel, panel.isKeyWindow, let editor = panel.firstResponder as? NSTextView else { return false }
        return !editor.string.isEmpty
    }

    /// Hands keyboard focus back to the app the user is working in, if the notch took it
    /// (for example for a search field). Call before sending keystrokes to that app.
    public func releaseKeyboardFocus() {
        guard let panel, panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        // Ordering a key window out makes the system return key status to the active app.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Takes the chosen size: the open notch, how much its pages are enlarged, and the room
    /// and enlargement of what shows beside the closed notch.
    private func apply(_ size: NotchSize) {
        viewModel.openSize = size.openSize
        viewModel.scale = size.scale
        viewModel.edgeScale = size.edgeScale
        viewModel.activitySideWidth = size.activitySideWidth
        refreshOpenSize()
    }

    /// Lets a page have a taller sheet than the usual one, or (with nil) the usual one again.
    /// The notch grows downwards for it while that page is the one shown; its width never changes.
    public func setSheetHeight(_ height: CGFloat?, forPage id: String) {
        guard pageSheetHeights[id] != height else { return }
        pageSheetHeights[id] = height
        refreshOpenSize()
    }

    /// Gives the open notch the height the page on show asks for. Growing, the window is made
    /// larger first and the shape follows; shrinking, the shape goes first and the window
    /// after it, so nothing is ever cut off in between.
    private func refreshOpenSize() {
        let size = settings.notchSize
        let wanted = viewModel.registry.selectedID.flatMap { pageSheetHeights[$0] }
        let height = PageHeight.open(
            sheetHeight: wanted, size: size, screenHeight: currentScreenFrame?.height ?? size.openSize.height)
        let target = CGSize(width: size.openSize.width, height: height)
        guard target != viewModel.openSize else { return }
        let isGrowing = target.height > viewModel.openSize.height
        if isGrowing, let geometry {
            panel?.setFrame(geometry.openRect(size: target), display: true)
        }
        // A page that gets lower under the pointer (a row done, an editor closed, a picker
        // in place of a long day) would read as the pointer leaving, and the notch would
        // close on what was just clicked. It waits for the pointer to come back instead.
        if let geometry, geometry.shrinkingLeavesOutside(NSEvent.mouseLocation, from: viewModel.openSize, to: target) {
            stateMachine.hold()
        }
        viewModel.openSize = target
        guard !isGrowing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, let geometry = self.geometry, self.viewModel.openSize == target else { return }
            self.panel?.setFrame(geometry.openRect(size: target), display: true)
        }
    }

    /// Shows the page with this id; ignored when no such page is registered.
    public func selectPage(id: String) {
        viewModel.registry.select(id)
    }

    // MARK: - Live activities

    /// Shows the activity beside the closed notch, or queues it behind a more important one.
    /// Presenting an id that is already showing refreshes it.
    public func present(_ activity: NotchLiveActivity) {
        activityContents[activity.request.id] = activity
        activityQueue.present(activity.request, at: Date())
        activityQueueChanged()
    }

    public func dismissActivity(id: String) {
        activityQueue.dismiss(id: id, at: Date())
        activityQueueChanged()
    }

    /// Things that rest beside the closed notch while they are true, by id: the track playing,
    /// Caps Lock being on. One shows at a time.
    private var restingActivities: [String: NotchLiveActivity] = [:]

    /// Sets, refreshes or (with nil) takes away a thing that rests beside the closed notch for
    /// as long as it is true, such as the track that is playing. Of several, the most important
    /// shows and the others come back when it goes. Anything shown for a while appears over
    /// it, and it comes back after.
    public func setRestingActivity(_ activity: NotchLiveActivity?, id: String) {
        restingActivities[id] = activity
        let chosen = Self.restingChoice(restingActivities.mapValues(\.request.priority)).flatMap { restingActivities[$0] }
        if let previous = activityQueue.restingID, previous != chosen?.request.id {
            activityContents[previous] = nil
        }
        if let chosen {
            activityContents[chosen.request.id] = chosen
        }
        activityQueue.setResting(chosen?.request)
        activityQueueChanged()
    }

    /// The id of the resting thing to show: the most important, and of equals the first by id.
    nonisolated static func restingChoice(_ priorities: [String: Int]) -> String? {
        priorities.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// The change of what shows on the closed notch that waits for a notice's content to fade.
    private var pendingActivityChange: DispatchWorkItem?

    private func activityQueueChanged() {
        let live = Set(activityQueue.waitingIDs + [activityQueue.current?.id, activityQueue.restingID].compactMap { $0 })
        let next = activityQueue.current.flatMap { activityContents[$0.id] }
        let nextIsResting = activityQueue.current != nil && activityQueue.current?.id == activityQueue.restingID
        pendingActivityChange?.cancel()
        pendingActivityChange = nil
        // A notice that goes lets what is on it fade first, then the plate shrinks; the two at
        // once showed an empty black plate, then its text again below the shrinking notch.
        if let shown = viewModel.activity, shown.dropSize != nil, shown.request.id != next?.request.id,
           !viewModel.isOpen, !viewModel.isNoticeLeaving {
            setNoticeLeaving(true)
            let change = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingActivityChange = nil
                self.showActivity(next, isResting: nextIsResting, live: live)
                self.setNoticeLeaving(false)
            }
            pendingActivityChange = change
            DispatchQueue.main.asyncAfter(deadline: .now() + NotchRootView.noticeFadeTime, execute: change)
        } else {
            showActivity(next, isResting: nextIsResting, live: live)
            setNoticeLeaving(false)
        }
        scheduleNextActivityDeadline()
    }

    private func setNoticeLeaving(_ isLeaving: Bool) {
        viewModel.isNoticeLeaving = isLeaving
        mirrors.values.forEach { $0.model.isNoticeLeaving = isLeaving }
    }

    private func showActivity(_ activity: NotchLiveActivity?, isResting: Bool, live: Set<String>) {
        activityContents = activityContents.filter { live.contains($0.key) || $0.key == activity?.request.id }
        viewModel.activity = activity
        viewModel.activityIsResting = isResting
        // Every display that shows the notch shows what is beside it.
        mirrors.values.forEach {
            $0.model.activity = viewModel.activity
            $0.model.activityIsResting = viewModel.activityIsResting
        }
        applyFullScreenHiding()
        refreshClickCatcher()
    }

    private func scheduleNextActivityDeadline() {
        activityTimer?.invalidate()
        activityTimer = nil
        if let deadline = activityQueue.nextDeadline {
            activityTimer = makeTimer(after: max(deadline.timeIntervalSinceNow, 0), repeats: false) { controller in
                controller.activityQueue.advance(to: Date())
                controller.activityQueueChanged()
            }
        }
    }

    // MARK: - Screen

    private func candidates(_ screens: [NSScreen]) -> [DisplayChooser.Candidate] {
        let pointer = NSEvent.mouseLocation
        return screens.map { screen in
            DisplayChooser.Candidate(
                hasNotch: screen.safeAreaInsets.top > 0,
                isMain: screen == NSScreen.main,
                containsPointer: DisplayChooser.display(screen.frame, holds: pointer))
        }
    }

    /// Which of these displays the notch is on now.
    private func currentIndex(among screens: [NSScreen]) -> Int? {
        currentScreenFrame.flatMap { frame in screens.firstIndex { $0.frame == frame } }
    }

    /// The display the settings ask for, among those connected now.
    private func chosenScreen() -> NSScreen? {
        let screens = NSScreen.screens
        return DisplayChooser.choose(
            settings.displayMode, among: candidates(screens), current: currentIndex(among: screens)
        ).map { screens[$0] }
    }

    /// For automated checks on a Mac whose only display has a notch: lay out as if it had none.
    public var treatsDisplaysAsNotchless = false

    /// Where the notch is and how large on this display.
    private func geometry(for screen: NSScreen) -> NotchGeometry {
        var descriptor = ScreenDescriptor(screen: screen)
        if treatsDisplaysAsNotchless {
            descriptor.safeAreaTop = 0
            descriptor.auxLeftWidth = nil
            descriptor.auxRightWidth = nil
        }
        return NotchGeometry(screen: descriptor, style: settings.pillStyle ? .pill : .attached)
    }

    private func layoutForCurrentScreen() {
        guard let screen = chosenScreen() else {
            geometry = nil
            panel?.orderOut(nil)
            layoutMirrors()
            return
        }
        currentScreenFrame = screen.frame
        guard !isHiddenByUser else { return }
        let geometry = geometry(for: screen)
        self.geometry = geometry
        viewModel.closedSize = geometry.closedRect.size
        viewModel.idleSize = geometry.restsAsBar ? geometry.idleRect.size : nil
        viewModel.hasPhysicalNotch = geometry.hasPhysicalNotch
        viewModel.isPill = geometry.isPill

        let panel = self.panel ?? makePanel()
        panel.setFrame(geometry.openRect(size: viewModel.openSize), display: true)
        panel.orderFrontRegardless()
        layoutMirrors()
        checkFullScreen()
    }

    // MARK: - Full screen

    /// Looks at which displays have an app full screen on them.
    private func checkFullScreen() {
        let screens = NSScreen.screens
        // Window bounds are measured down from the top of the main display.
        let mainHeight = screens.first?.frame.height ?? 0
        let displays = screens.map { CGRect(x: $0.frame.minX, y: mainHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows = list.compactMap { info -> FullScreenRule.Window? in
            guard let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap({ CGRect(dictionaryRepresentation: $0 as CFDictionary) }),
                  let layer = info[kCGWindowLayer as String] as? Int
            else { return nil }
            return FullScreenRule.Window(bounds: bounds, layer: layer, isOwn: (info[kCGWindowOwnerPID as String] as? Int) == ownPID)
        }
        let covered = FullScreenRule.coveredDisplays(windows: windows, displays: displays)
        fullScreenDisplays = Set(covered.compactMap { Self.displayID(of: screens[$0]) })
        applyFullScreenHiding()
    }

    /// Hides the notch on a display with a full-screen app, unless it is open or has a notice.
    private func applyFullScreenHiding() {
        let showsNotice = viewModel.activity != nil && !viewModel.activityIsResting
        let current = NSScreen.screens.first { $0.frame == currentScreenFrame }.flatMap(Self.displayID)
        viewModel.isHiddenForFullScreen = FullScreenRule.hidesNotch(
            isCovered: current.map(fullScreenDisplays.contains) ?? false, isEnabled: settings.hidesInFullScreen,
            isOpen: stateMachine.isPresented, showsNotice: showsNotice)
        for (id, mirror) in mirrors {
            mirror.model.isHiddenForFullScreen = FullScreenRule.hidesNotch(
                isCovered: fullScreenDisplays.contains(id), isEnabled: settings.hidesInFullScreen,
                isOpen: false, showsNotice: showsNotice)
        }
        // Opening, closing, moving to another display and hiding all pass through here.
        refreshClickCatcher()
    }

    /// Shows the closed notch on every other display the settings ask for, and puts away the
    /// mirror of a display that is gone, or that now has the notch that answers.
    private func layoutMirrors() {
        let screens = NSScreen.screens
        let others = isHiddenByUser
            ? []
            : DisplayChooser.others(settings.displayMode, among: candidates(screens), current: currentIndex(among: screens))
        var shown: Set<CGDirectDisplayID> = []
        for screen in others.map({ screens[$0] }) {
            guard let id = Self.displayID(of: screen) else { continue }
            shown.insert(id)
            let mirror = mirrors[id] ?? makeMirror()
            mirrors[id] = mirror
            let geometry = geometry(for: screen)
            let model = mirror.model
            model.closedSize = geometry.closedRect.size
            model.idleSize = geometry.restsAsBar ? geometry.idleRect.size : nil
            model.hasPhysicalNotch = geometry.hasPhysicalNotch
            model.isPill = geometry.isPill
            model.openSize = settings.notchSize.openSize
            model.scale = viewModel.scale
            model.edgeScale = viewModel.edgeScale
            model.activitySideWidth = viewModel.activitySideWidth
            model.activity = viewModel.activity
            mirror.panel.setFrame(geometry.openRect(size: model.openSize), display: true)
            mirror.panel.orderFrontRegardless()
        }
        let connected = Set(screens.compactMap(Self.displayID))
        for (id, mirror) in mirrors where !shown.contains(id) {
            mirror.panel.orderOut(nil)
            if !connected.contains(id) {
                mirrors[id] = nil
            }
        }
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// A window that only shows the closed notch: it has no pages and never takes the pointer.
    private func makeMirror() -> Mirror {
        let model = NotchViewModel()
        let panel = NotchPanel()
        panel.contentView = NotchHostingView(rootView: NotchRootView(model: model))
        panel.sharingType = settings.hidesFromCapture ? .none : .readOnly
        return Mirror(panel: panel, model: model)
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel()
        panel.contentView = FirstMouseHostingView(rootView: NotchRootView(model: viewModel))
        panel.sharingType = settings.hidesFromCapture ? .none : .readOnly
        self.panel = panel
        return panel
    }

    private func screenParametersChanged() {
        send(.forceClose)
        layoutForCurrentScreen()
    }

    // MARK: - Input

    private func isInside(_ point: CGPoint) -> Bool {
        guard let geometry else { return false }
        // Out of the way of a full-screen app, the notch is not there to be touched.
        if viewModel.isHiddenForFullScreen, !stateMachine.isPresented { return false }
        let rect = stateMachine.isPresented
            ? geometry.openHitRect(size: viewModel.openSize)
            : geometry.hoverRect(padding: settings.interactionPadding, isAwake: isAwake)
        return rect.contains(point)
    }

    /// The closed notch is at its full size: the pointer is on it, or something shows beside
    /// it. Otherwise, where there is no hardware notch, it waits as a bar and is reached there.
    private var isAwake: Bool {
        viewModel.isTouched || viewModel.activity != nil
    }

    private func pointerMoved(to point: CGPoint) {
        guard !isHiddenByUser else { return }
        // Following the pointer: the closed notch moves to the display the pointer entered.
        // Only when it is another display: laying the windows out again at every move of the
        // pointer makes the display stutter.
        if settings.displayMode.followsPointer, !stateMachine.isPresented,
           let frame = currentScreenFrame, !DisplayChooser.display(frame, holds: point),
           chosenScreen()?.frame != frame {
            layoutForCurrentScreen()
        }
        let inside = isInside(point)
        touchChanged(to: inside && !stateMachine.isPresented)
        if !inside, stateMachine.state == .open {
            stateMachine.isTyping = isTypingInPanel
        }
        send(.pointerMoved(inside: inside))
    }

    /// A menu put up from the open panel, such as a clip's context menu, holds the panel open
    /// until the menu is gone; then the pointer decides again.
    private func menuTracking(began: Bool) {
        if began {
            guard menuDepth > 0 || (stateMachine.state == .open && isInside(NSEvent.mouseLocation)) else { return }
            menuDepth += 1
        } else if menuDepth > 0 {
            menuDepth -= 1
        }
        let isTracking = menuDepth > 0
        guard stateMachine.isMenuTracking != isTracking else { return }
        stateMachine.isMenuTracking = isTracking
        if !isTracking {
            // A choice made from a long menu leaves the pointer far from the panel. While
            // something is being typed in it, that is not the pointer leaving: the panel
            // waits for the pointer to come back.
            if panel?.isKeyWindow == true, !isInside(NSEvent.mouseLocation) {
                stateMachine.hold()
            }
            pointerMoved(to: NSEvent.mouseLocation)
        }
    }

    /// A menu runs the main loop in its own mode; outside that mode no menu is up, whatever
    /// was or was not announced, so a missed announcement cannot hold the panel open for good.
    private func forgetMenuIfGone() {
        guard menuDepth > 0, RunLoop.main.currentMode != .eventTracking else { return }
        menuDepth = 0
        stateMachine.isMenuTracking = false
    }

    /// Files dragged towards the closed notch open it, whatever the hover setting, so they can
    /// be dropped; and from a little way off, so the pointer need not reach the screen's edge.
    private func filesDragged(to point: CGPoint) {
        guard !isHiddenByUser, !stateMachine.isPresented, let geometry, geometry.dragRect.contains(point) else { return }
        send(.clicked(inside: true))
        onFileDrag?()
    }

    private func clicked(at point: CGPoint) {
        guard !isHiddenByUser else { return }
        // A click on a notice that takes something back does that, and the notice goes.
        if !stateMachine.isPresented, let activity = viewModel.activity, let action = activity.onClick,
           let area = activityClickArea {
            if area.contains(point) {
                AraHaptics.play(.tap)
                dismissActivity(id: activity.request.id)
                action()
                return
            }
        }
        // A click on a live activity opens the page the activity belongs to.
        if !stateMachine.isPresented, let pageID = viewModel.activity?.pageID, let area = activityClickArea {
            if area.contains(point) {
                pageForNextOpen = pageID
                send(.clicked(inside: true))
                return
            }
        }
        send(.clicked(inside: isInside(point)))
    }

    /// Where what shows on the closed notch is clicked, on the screen; nil when nothing shows.
    private var activityClickArea: CGRect? {
        guard let geometry, let activity = viewModel.activity else { return nil }
        return NotchClickArea.rect(
            closedRect: geometry.closedRect, dropCard: activity.dropSize, sideWidth: viewModel.shownActivitySideWidth,
            scale: viewModel.scale)
    }

    /// Puts the click catcher over what shows on the closed notch, or away.
    private func refreshClickCatcher() {
        guard !isHiddenByUser,
              NotchClickArea.takesClicks(
                isOpen: stateMachine.isPresented, showsSomething: viewModel.activity != nil,
                isHidden: viewModel.isHiddenForFullScreen),
              let area = activityClickArea
        else {
            clickCatcher?.orderOut(nil)
            return
        }
        let catcher = clickCatcher ?? NotchClickCatcher()
        clickCatcher = catcher
        catcher.sharingType = settings.hidesFromCapture ? .none : .readOnly
        catcher.setFrame(area, display: false)
        catcher.orderFrontRegardless()
    }

    /// On a page that scrolls sideways, a mouse wheel's turn up or down becomes a scroll along
    /// the page. Trackpads, and the tab row with its own gestures, are left alone.
    private func sidewaysScroll(for event: NSEvent) -> NSEvent? {
        guard stateMachine.isPresented, event.window === panel, let geometry,
              let id = viewModel.registry.selectedID, viewModel.pages[id]?.wheelScrollsSideways == true,
              !geometry.headerRect(size: viewModel.openSize).contains(NSEvent.mouseLocation),
              WheelRedirect.sideways(
                  deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY),
                  isTouch: !event.phase.isEmpty || !event.momentumPhase.isEmpty) != nil,
              let turned = event.cgEvent?.copy()
        else { return nil }
        // The same turn is written three ways in the event: lines, fractions of a line, and
        // points. All are read before any is written, and lines are written first, because
        // writing lines makes the system work out the other two again.
        let lines = turned.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let fraction = turned.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let points = turned.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        turned.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        turned.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: lines)
        turned.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        turned.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fraction)
        turned.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        turned.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: points)
        return NSEvent(cgEvent: turned)
    }

    private func scrolled(_ event: NSEvent) {
        guard !isHiddenByUser, let geometry else { return }
        let pointer = NSEvent.mouseLocation
        let phase: SwipeAccumulator.Phase?
        if !event.momentumPhase.isEmpty {
            phase = .momentum
        } else if event.phase.contains(.began) {
            phase = .began
        } else if event.phase.contains(.changed) {
            phase = .changed
        } else if event.phase.contains(.ended) {
            phase = .ended
        } else if event.phase.contains(.cancelled) {
            phase = .cancelled
        } else {
            // A mouse wheel has no gesture phases.
            phase = nil
        }

        let onHeader = stateMachine.isPresented && event.window === panel
            && geometry.headerRect(size: viewModel.openSize).insetBy(dx: 0, dy: -NotchGeometry.hoverPadding).contains(pointer)
        let onClosedNotch = !stateMachine.isPresented
            && geometry.hoverRect(padding: settings.interactionPadding, isAwake: isAwake).contains(pointer)

        // A swipe down on the closed notch opens it; a swipe up on the tab row closes it.
        if settings.swipeToOpen, onHeader || onClosedNotch {
            verticalSwipe.threshold = settings.swipeSensitivity.threshold
            let verticalPhase: VerticalSwipeDetector.Phase = switch phase {
            case .began: .began
            case .changed: .changed
            case .ended: .ended
            case .cancelled: .cancelled
            case .momentum: .momentum
            case nil: .wheel
            }
            let fingerDeltaY = VerticalSwipeDetector.fingerDelta(
                scrollingDeltaY: event.scrollingDeltaY, isNatural: event.isDirectionInvertedFromDevice)
            switch verticalSwipe.add(deltaX: event.scrollingDeltaX, fingerDeltaY: fingerDeltaY, phase: verticalPhase) {
            case .down where onClosedNotch:
                send(.clicked(inside: true))
                return
            // A swipe up on the closed notch sweeps away what shows beside it.
            case .up where onClosedNotch && viewModel.activity != nil:
                activityQueue.hideCurrent(at: Date())
                activityQueueChanged()
                AraHaptics.play(.tap)
                return
            case .up where onHeader:
                send(.forceClose)
                return
            default:
                break
            }
        }

        // A sideways swipe on the closed notch belongs to what shows beside it: the next or
        // the previous track, for one.
        if onClosedNotch, let phase, let onSwipe = viewModel.activity?.onSwipe {
            if let direction = swipe.add(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, phase: phase) {
                AraHaptics.play(.tap)
                onSwipe(direction)
            }
            return
        }

        // Only the header strip switches pages, so pages are free to scroll their own content.
        // A mouse wheel does not switch pages.
        guard onHeader, let phase else { return }

        switch swipe.add(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, phase: phase) {
        case .next: viewModel.registry.selectNext()
        case .previous: viewModel.registry.selectPrevious()
        case nil: break
        }
    }

    private func openOnHoverChanged(to isEnabled: Bool) {
        stateMachine.openOnHover = isEnabled
        if !isEnabled, stateMachine.state == .hoverPending {
            send(.forceClose)
        }
    }

    // MARK: - State machine

    private func send(_ event: NotchStateMachine.Event) {
        for effect in stateMachine.handle(event) {
            perform(effect)
        }
        updateSafetyNet()
    }

    private func perform(_ effect: NotchStateMachine.Effect) {
        switch effect {
        case .scheduleHoverTimer:
            hoverTimer = makeTimer(after: settings.hoverDelay, repeats: false) { $0.send(.hoverDelayElapsed) }
        case .cancelHoverTimer:
            hoverTimer?.invalidate()
            hoverTimer = nil
        case .scheduleCloseTimer:
            closeTimer = makeTimer(after: ShellSettingsStore.closeDelay, repeats: false) { $0.send(.closeDelayElapsed) }
        case .cancelCloseTimer:
            closeTimer?.invalidate()
            closeTimer = nil
        case .didOpen:
            // A fixed start page is shown on every open; otherwise the last used page stays.
            if let pageID = pageForNextOpen {
                viewModel.registry.select(pageID)
            } else if let startPage = settings.startPage {
                viewModel.registry.select(startPage)
            }
            pageForNextOpen = nil
            viewModel.isTouched = false
            viewModel.isOpen = true
            applyFullScreenHiding()
            panel?.ignoresMouseEvents = false
            AraHaptics.play(.tap)
        case .didClose:
            viewModel.isOpen = false
            applyFullScreenHiding()
            // A pin lasts as long as the opening it was made in.
            stateMachine.isPinned = false
            stateMachine.isTyping = false
            viewModel.isPinned = stateMachine.staysOpen
            // What was swept away from beside the notch is back after the next visit.
            activityQueue.unhideResting()
            activityQueueChanged()
            AraTooltipCenter.shared.hide()
            releaseKeyboardFocus()
            panel?.ignoresMouseEvents = true
            swipe = SwipeAccumulator()
        }
    }

    /// While the notch is not closed, re-reads the pointer position on a timer so that a
    /// missed mouse event can never leave the panel stuck open. Idle when closed.
    private func updateSafetyNet() {
        if stateMachine.state == .closed {
            safetyNetTimer?.invalidate()
            safetyNetTimer = nil
        } else if safetyNetTimer == nil {
            safetyNetTimer = makeTimer(after: Self.safetyNetInterval, repeats: true) {
                $0.forgetMenuIfGone()
                $0.pointerMoved(to: NSEvent.mouseLocation)
            }
        }
    }

    private func makeTimer(
        after interval: TimeInterval,
        repeats: Bool,
        action: @escaping @MainActor (NotchController) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        // Common modes keep the timers running while a menu or a drag is tracking.
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
