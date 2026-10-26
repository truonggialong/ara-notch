import AppKit
import ApplicationServices
import NotchShell
import SwiftUI
import TranslateCore

/// Reads what is selected in the app in front, through Accessibility.
@MainActor
enum SelectionReader {
    /// The text selected in the focused element of the app in front, and that app's process id.
    /// Nil without Accessibility permission, when this app is in front, and for password fields.
    static func selection() -> (text: String, pid: pid_t)? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // An app that is busy must not hold this one up.
        AXUIElementSetMessagingTimeout(element, 0.3)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        let field = focused as! AXUIElement
        var subrole: CFTypeRef?
        if AXUIElementCopyAttributeValue(field, kAXSubroleAttribute as CFString, &subrole) == .success,
           subrole as? String == kAXSecureTextFieldSubrole as String {
            return nil
        }
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(field, kAXSelectedTextAttribute as CFString, &selection) == .success,
              let text = selection as? String
        else { return nil }
        return (text, app.processIdentifier)
    }
}

/// State of the bar shown beside a fresh selection.
@MainActor
final class SmartSelectionViewModel: ObservableObject {
    @Published var actions: [SelectionAction] = []
    var onAction: ((SelectionAction) -> Void)?
}

/// Smart Selection: after the user selects text with the mouse in any app, a small bar of
/// actions appears beside the pointer. The text is read through Accessibility and leaves the
/// Mac only when the user presses Translate or Search.
@MainActor
final class SmartSelectionController {
    /// Seconds the bar stays when nothing is done with it.
    private static let lifetime: TimeInterval = 6

    var onTranslate: ((String) -> Void)?

    private let viewModel = SmartSelectionViewModel()
    private var monitors: [Any] = []
    private var tracker = SelectionTracker()
    private var downPoint: CGPoint?
    private var current: SmartSelection?
    private var panel: NSPanel?
    private var hideTimer: Timer?

    init() {
        viewModel.onAction = { [weak self] action in self?.perform(action) }
    }

    func setEnabled(_ isEnabled: Bool) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hide()
        guard isEnabled else { return }
        // Global monitors see other apps' events only, so a click on the bar itself is not one.
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.downPoint = NSEvent.mouseLocation
            self?.hide()
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            self?.mouseUp(clickCount: event.clickCount)
        }
        let other = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .scrollWheel, .rightMouseDown]) {
            [weak self] _ in self?.hide()
        }
        monitors = [down, up, other].compactMap { $0 }
    }

    private func mouseUp(clickCount: Int) {
        let up = NSEvent.mouseLocation
        guard let down = downPoint, SelectionGesture.maySelect(down: down, up: up, clickCount: clickCount) else {
            tracker.reset()
            return
        }
        // A moment later, when the app has made its selection known.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let found = SelectionReader.selection()
            let selection = SmartSelection(found?.text)
            guard self.tracker.shouldShow(selection, pid: found?.pid ?? 0), let selection else { return }
            self.show(selection)
        }
    }

    /// Shows the bar for a selection, just above the pointer.
    func show(_ selection: SmartSelection) {
        current = selection
        viewModel.actions = selection.actions

        let panel = self.panel ?? makePanel()
        let size = panel.contentView?.fittingSize ?? CGSize(width: 200, height: 32)
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y + 14)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        let timer = Timer(timeInterval: Self.lifetime, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    private func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel?.orderOut(nil)
        current = nil
    }

    private func perform(_ action: SelectionAction) {
        guard let selection = current else { return }
        hide()
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selection.text, forType: .string)
        case .translate:
            onTranslate?(selection.text)
        case .search:
            if let url = selection.searchURL {
                NSWorkspace.shared.open(url)
            }
        case .openLink:
            if let url = selection.link {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func makePanel() -> NSPanel {
        // Non-activating and never key: the app in front keeps its selection and its focus.
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: SmartSelectionBar(model: viewModel))
        self.panel = panel
        return panel
    }
}

/// The bar of actions shown beside a fresh selection.
struct SmartSelectionBar: View {
    @ObservedObject var model: SmartSelectionViewModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.actions, id: \.self) { action in
                // Icons only: the bar is gone in a few seconds, and a glance must be enough.
                AraIconButton(Self.icon(for: action), look: .bare, help: L10n.string("selection.\(action.rawValue)")) {
                    model.onAction?(action)
                }
            }
        }
        .padding(3)
        .fixedSize()
        .araSurface(Capsule())
        .araHue(.sky)
    }

    private static func icon(for action: SelectionAction) -> AraIcon {
        switch action {
        case .copy: .copy
        case .translate: .translate
        case .search: .search
        case .openLink: .openLink
        }
    }
}
