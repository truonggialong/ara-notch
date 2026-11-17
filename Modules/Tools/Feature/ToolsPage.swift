import NotchShell
import SwiftUI

/// The tools page: everything that otherwise takes a shortcut or the menu bar, as round
/// buttons with their names under them. They are all one colour; colour says that a tool is
/// on (red for recording, yellow for keeping awake, orange for a countdown), and a tool that
/// runs shows its number in place of its icon.
struct ToolsPage: View {
    @Environment(\.araScale) private var ui
    let tools: [NotchTool]
    @ObservedObject var states: ToolStates
    @StateObject private var held = HeldTool()

    var body: some View {
        // Rows across the page while they fit, else sideways (`AraRail`).
        AraRail(tools, itemSize: CGSize(width: 78, height: 72), spacing: 6) { tool in
            ToolButton(tool: tool, state: states.states[tool.id], held: held)
        }
        .overlay {
            // A tool held open its choices over the page; a click beside them closes them.
            if let id = held.openID, let options = tools.first(where: { $0.id == id })?.options {
                ZStack {
                    Color.black.opacity(0.35)
                        .contentShape(Rectangle())
                        .onTapGesture { held.openID = nil }
                    options { held.openID = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(AraTheme.hover, value: held.openID)
    }
}

/// The tool whose choices are open, and whether the press that opened them is still to be
/// let go (its click then does nothing more).
@MainActor
final class HeldTool: ObservableObject {
    @Published var openID: String?
    var swallowsClick = false
}

/// What a tool shows while it is on.
public struct NotchToolState: Equatable {
    public enum Tone: Equatable {
        /// Recording, the microphone: red.
        case alert
        /// Keeping the Mac awake: yellow.
        case awake
        /// A countdown: orange.
        case timer
    }

    public var tone: Tone
    /// A short number in place of the icon, such as the time left.
    public var badge: String?

    public init(tone: Tone, badge: String? = nil) {
        self.tone = tone
        self.badge = badge
    }

    var color: Color {
        switch tone {
        case .alert: Color(red: 1, green: 0.36, blue: 0.34)
        case .awake: Color(red: 0.98, green: 0.80, blue: 0.22)
        case .timer: AraPalette.brand
        }
    }
}

/// The tools that are on now, by tool.
@MainActor
public final class ToolStates: ObservableObject {
    @Published public var states: [String: NotchToolState] = [:]
    public init() {}
}

private struct ToolButton: View {
    @Environment(\.araScale) private var ui
    let tool: NotchTool
    let state: NotchToolState?
    @ObservedObject var held: HeldTool
    @StateObject private var hover = AraHover()

    var body: some View {
        Button {
            // The click that ends a hold has already opened the choices.
            if held.swallowsClick {
                held.swallowsClick = false
                return
            }
            tool.action()
        } label: {
            VStack(spacing: 6 * ui) {
                ZStack {
                    Circle().fill(state?.color ?? Color.white.opacity(hover.isHovered ? AraNotchWhite.hover : AraNotchWhite.card))
                    if let badge = state?.badge {
                        Text(badge)
                            .font(.system(size: 11 * ui, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 3 * ui)
                    } else {
                        tool.icon.image
                            .font(.system(size: 15 * ui, weight: .medium))
                    }
                }
                .foregroundStyle(state == nil ? AraPalette.ink : Color.black.opacity(0.85))
                .frame(width: 40 * ui, height: 40 * ui)
                .scaleEffect(hover.isHovered ? AraTheme.hoverLift : 1)
                Text(L10n.string("tools.\(tool.id)"))
                    .font(.system(size: 10.5 * ui, weight: .medium))
                    .foregroundStyle(AraPalette.ink.opacity(hover.isHovered ? 1 : 0.78))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .animation(AraTheme.hover, value: hover.isHovered)
            .animation(AraTheme.hover, value: state)
        }
        .buttonStyle(AraPressStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                guard tool.options != nil else { return }
                held.swallowsClick = true
                held.openID = tool.id
                AraHaptics.play(.tap)
            })
        .onHover { hover.isHovered = $0 }
        .accessibilityLabel(L10n.string("tools.\(tool.id)"))
        .accessibilityAction(named: L10n.string("tools.moreChoices")) {
            if tool.options != nil { held.openID = tool.id }
        }
    }
}
