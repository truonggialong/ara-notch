import NotchCore
import SwiftUI

/// Settings › General › Notch: the notch as it will look, to be arranged by hand. The round
/// buttons stand in their places around a small notch: drag one onto another place to move
/// it, click + on an empty place to add one, and use a button's menu to change or remove it.
/// Under it, the sizes and backgrounds as cards that show what they look like.
public struct NotchLayoutEditor: View {
    @ObservedObject var settings: ShellSettings
    /// Every page, for the buttons that open one.
    let pages: [PageDescriptor]

    public init(settings: ShellSettings, pages: [PageDescriptor]) {
        self.settings = settings
        self.pages = pages
    }

    static let previewSize = CGSize(width: 380, height: 136)
    @StateObject private var picking = SlotPicking()
    private static let notch = CGSize(width: 210, height: 84)
    private static let slot: CGFloat = 30

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            preview
            Text(L10n.string("settings.layout.hint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            cards(title: L10n.string("settings.notchSize")) {
                ForEach(NotchSize.allCases, id: \.self) { size in
                    sizeCard(size)
                }
            }
            cards(title: L10n.string("settings.material")) {
                ForEach(NotchMaterial.allCases, id: \.self) { material in
                    materialCard(material)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - The notch and its buttons

    private var preview: some View {
        let area = Self.previewSize
        let notchOrigin = CGPoint(x: (area.width - Self.notch.width) / 2, y: 0)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.16))
            UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(width: Self.notch.width, height: Self.notch.height)
                .overlay(alignment: .top) {
                    // The camera.
                    Capsule().fill(Color(white: 0.12)).frame(width: 60, height: 8).padding(.top, 3)
                }
                .offset(x: notchOrigin.x)
            ForEach(OrbitSlot.allCases, id: \.self) { slot in
                let centre = Self.centre(of: slot, notchOrigin: notchOrigin)
                slotView(slot)
                    .position(x: centre.x, y: centre.y)
            }
        }
        .frame(width: area.width, height: area.height)
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity)
    }

    /// Places as `OrbitLayout.centre` lays them out, drawn smaller.
    private static func centre(of slot: OrbitSlot, notchOrigin: CGPoint) -> CGPoint {
        let point = OrbitLayout.centre(of: slot, openSize: notch, scale: 0.62)
        return CGPoint(x: notchOrigin.x + point.x, y: notchOrigin.y + point.y)
    }

    @ViewBuilder
    private func slotView(_ slot: OrbitSlot) -> some View {
        let action = settings.orbitLayout.actions[slot]
        Button {
            picking.slot = slot
        } label: {
            ZStack {
                if let action {
                    Circle().fill(Color.black)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75))
                    Image(systemName: symbol(of: action))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Circle().strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .frame(width: Self.slot, height: Self.slot)
            .contentShape(Circle())
        }
        .buttonStyle(AraPressStyle())
        .help(action.map(title(of:)) ?? L10n.string("settings.layout.add"))
        .popover(isPresented: Binding(
            get: { picking.slot == slot },
            set: { if !$0, picking.slot == slot { picking.slot = nil } }
        ), arrowEdge: .bottom) {
            choiceList(for: slot, current: action)
        }
        .draggable(slot.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first.flatMap(OrbitSlot.init(rawValue:)), source != slot else { return false }
            var layout = settings.orbitLayout
            layout.swap(source, slot)
            settings.orbitLayout = layout
            return true
        }
    }

    /// What a place can hold, to choose from; the button there now is ticked.
    private func choiceList(for slot: OrbitSlot, current: OrbitAction?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(choices, id: \.storedName) { choice in
                Button {
                    var layout = settings.orbitLayout
                    // A button stands in one place only: taking it here takes it from elsewhere.
                    for (other, existing) in layout.actions where existing == choice && other != slot {
                        layout.set(nil, at: other)
                    }
                    layout.set(choice, at: slot)
                    settings.orbitLayout = layout
                    picking.slot = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(of: choice)).frame(width: 18)
                        Text(title(of: choice))
                        Spacer(minLength: 12)
                        if choice == current { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if current != nil {
                Divider().padding(.vertical, 3)
                Button(role: .destructive) {
                    var layout = settings.orbitLayout
                    layout.set(nil, at: slot)
                    settings.orbitLayout = layout
                    picking.slot = nil
                } label: {
                    Label(L10n.string("settings.layout.remove"), systemImage: "minus.circle")
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(minWidth: 200)
    }

    private var choices: [OrbitAction] {
        [.explore, .settings, .pin] + pages.map { .page($0.id) }
    }

    private func title(of action: OrbitAction) -> String {
        switch action {
        case .explore: L10n.string("notch.explore")
        case .settings: L10n.string("notch.settings.tooltip")
        case .pin: L10n.string("notch.pin.off")
        case let .page(id): pages.first { $0.id == id }.map { L10n.string($0.titleKey) } ?? id
        }
    }

    private func symbol(of action: OrbitAction) -> String {
        switch action {
        case .explore: "square.grid.2x2"
        case .settings: "gearshape"
        case .pin: "pin"
        case let .page(id): pages.first { $0.id == id }?.symbolName ?? "square"
        }
    }

    // MARK: - Cards

    private func cards<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) { content() }
        }
    }

    private func sizeCard(_ size: NotchSize) -> some View {
        let isOn = settings.notchSize == size
        return Button {
            settings.notchSize = size
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    Color.clear.frame(height: 34)
                    UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6, style: .continuous)
                        .fill(Color.black)
                        .frame(width: 40 * size.scale, height: 14 * size.scale)
                        .overlay(
                            Text("Aa").font(.system(size: 7 * size.scale, weight: .semibold)).foregroundStyle(.white)
                                .padding(.top, 2), alignment: .center)
                }
                Text(L10n.string("settings.notchSize.\(size.rawValue)"))
                    .font(.system(size: 10.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(card(isOn: isOn))
        }
        .buttonStyle(.plain)
    }

    private func materialCard(_ material: NotchMaterial) -> some View {
        let isOn = settings.material == material
        return Button {
            settings.material = material
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    LinearGradient(
                        colors: [.orange.opacity(0.8), .purple.opacity(0.8), .blue.opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(material.shade(increasedContrast: false)))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(L10n.string("settings.material.\(material.rawValue)"))
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(card(isOn: isOn))
        }
        .buttonStyle(.plain)
    }

    private func card(isOn: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(isOn ? 0.1 : 0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? AraPalette.brand : Color.primary.opacity(0.08), lineWidth: isOn ? 2 : 1))
    }
}

/// Which place's choices are open.
@MainActor
final class SlotPicking: ObservableObject {
    @Published var slot: OrbitSlot?
}
