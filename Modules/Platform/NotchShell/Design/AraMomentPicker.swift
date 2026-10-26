import AppKit
import NotchCore
import SwiftUI

/// What the floating picker is choosing.
@MainActor
final class AraMomentModel: ObservableObject {
    @Published var title = ""
    @Published var moment = Date()
    var onDone: ((Date) -> Void)?
    var onCancel: (() -> Void)?
}

/// A small floating panel for choosing a day and a time by sight, for features that have
/// no page of the notch to show it on.
@MainActor
public final class AraMomentPicker {
    public static let shared = AraMomentPicker()

    private let model = AraMomentModel()
    private var panel: NSPanel?

    /// Shows the picker by the pointer. `onDone` gets the chosen moment; nothing is called
    /// when the user gives up.
    public func present(title: String, initial: Date, onDone: @escaping (Date) -> Void) {
        model.title = title
        model.moment = initial
        model.onDone = { [weak self] moment in
            self?.close()
            onDone(moment)
        }
        model.onCancel = { [weak self] in self?.close() }
        let panel = panel ?? makePanel()
        let size = AraMomentPickerView.size
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height - 12)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        }
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    public func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        // Non-activating: the app in front keeps its focus while a time is chosen.
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: AraMomentPickerView(model: model))
        self.panel = panel
        return panel
    }
}

struct AraMomentPickerView: View {
    static let size = CGSize(width: 500, height: 196)

    @ObservedObject var model: AraMomentModel

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            AraMonthCalendar(
                day: Binding(
                    get: { Calendar.current.startOfDay(for: model.moment) },
                    set: { model.moment = AraMoment.moment(on: $0, minutesOfDay: AraMoment.minutesOfDay(of: model.moment)) }))
            AraClockFace(minutesOfDay: Binding(
                get: { AraMoment.minutesOfDay(of: model.moment) },
                set: { model.moment = AraMoment.moment(on: model.moment, minutesOfDay: $0) }))
            VStack(alignment: .leading, spacing: 8) {
                Text(model.title)
                    .font(.system(size: 11))
                    .foregroundStyle(AraPalette.label)
                    .lineLimit(2)
                Text(Self.summary.string(from: model.moment))
                    .font(AraType.display(14))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                AraPillButton(L10n.string("picker.done"), icon: .confirm, isProminent: true) {
                    model.onDone?(model.moment)
                }
                AraPillButton(L10n.string("settings.cancel"), icon: .close) { model.onCancel?() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
        .padding(14)
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(AraPalette.ink)
        .araCard(radius: 18)
    }

    /// "Thu 15 Oct, 14:30".
    private static let summary: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return formatter
    }()
}
