import AppKit
import NotchCore
import SwiftUI

/// Shows the name of an icon button right away. The system's own tooltip waits about a second
/// and a half, which is too long when a button is nothing but an icon.
@MainActor
public final class AraTooltipCenter {
    public static let shared = AraTooltipCenter()

    /// How long the pointer rests on a button before its name shows.
    static let delay: TimeInterval = 0.28
    /// Moving on to a neighbouring button within this time shows its name at once.
    static let carryOver: TimeInterval = 0.7
    /// A name left on screen by a missed "pointer left" goes away by itself.
    static let longest: TimeInterval = 5

    private var panel: NSPanel?
    private weak var owner: NSView?
    private var pending: DispatchWorkItem?
    private var expiry: DispatchWorkItem?
    private var lastHidden = Date.distantPast

    func pointerEntered(_ view: NSView, text: String) {
        guard !text.isEmpty else { return }
        pending?.cancel()
        owner = view
        let show = DispatchWorkItem { [weak self, weak view] in
            guard let self, let view, self.owner === view else { return }
            self.show(text, for: view)
        }
        pending = show
        let wait = Date().timeIntervalSince(lastHidden) < Self.carryOver ? 0.03 : Self.delay
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: show)
    }

    func pointerLeft(_ view: NSView) {
        guard owner === view else { return }
        hide()
    }

    /// Takes the name away, for example when its button is pressed.
    public func hide() {
        pending?.cancel()
        pending = nil
        expiry?.cancel()
        expiry = nil
        owner = nil
        if panel?.isVisible == true {
            lastHidden = Date()
            panel?.orderOut(nil)
        }
    }

    private func show(_ text: String, for view: NSView) {
        guard let window = view.window, window.isVisible, let screen = window.screen ?? NSScreen.main else { return }
        let anchor = window.convertToScreen(view.convert(view.bounds, to: nil))
        let host = NSHostingView(rootView: AraTooltipLabel(text: text))
        let size = host.fittingSize
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.contentView = host
        let origin = TooltipPlacement.origin(anchor: anchor, size: size, screen: screen.frame)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        // Above the window the button is in, whatever that is.
        panel.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        panel.sharingType = window.sharingType
        panel.orderFrontRegardless()

        expiry?.cancel()
        let expire = DispatchWorkItem { [weak self] in self?.hide() }
        expiry = expire
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longest, execute: expire)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

/// The look of a tooltip: a small black pill with light text, day and night.
private struct AraTooltipLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(Color(white: 0.96))
            .background(Color(white: 0.1), in: Capsule())
            // Shows where the pill ends when it lies on the black of the notch.
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75))
            .fixedSize()
    }
}

/// Sits behind a control and tells the tooltip centre where the control is on screen.
struct AraTooltipAnchor: NSViewRepresentable {
    let text: String
    let isHovered: Bool

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        if isHovered {
            AraTooltipCenter.shared.pointerEntered(view, text: text)
        } else {
            AraTooltipCenter.shared.pointerLeft(view)
        }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) {
        AraTooltipCenter.shared.pointerLeft(view)
    }
}

public extension View {
    /// Names the view the moment the pointer rests on it. `isHovered` is the hover state the
    /// view already keeps for its own highlight.
    func araTooltip(_ text: String, isHovered: Bool) -> some View {
        // The anchor is an AppKit view; one behind every button made a page slow to build,
        // so it exists only while the pointer is on the button. Taking it away says it left.
        background {
            if isHovered {
                AraTooltipAnchor(text: text, isHovered: true).allowsHitTesting(false)
            }
        }
    }
}

/// Short taps on the trackpad that confirm an action. One switch in Settings turns all of
/// them on or off.
@MainActor
public enum AraHaptics {
    public static var isEnabled = true

    public enum Kind {
        /// Something snapped into place: a paste, a pin, a drop.
        case tap
        /// Something changed state: a switch, a tick.
        case change
        /// Something finished and wants attention.
        case finish
    }

    public static func play(_ kind: Kind) {
        guard isEnabled else { return }
        let pattern: NSHapticFeedbackManager.FeedbackPattern = switch kind {
        case .tap: .alignment
        case .change: .levelChange
        case .finish: .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
