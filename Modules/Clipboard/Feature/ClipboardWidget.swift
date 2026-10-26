import ClipboardCore
import NotchShell
import SwiftUI

/// The clipboard as a widget of the overview. Small: the newest clip, a click pastes it.
/// Wide: the three newest as cards in their kinds' colours, a click on one pastes it. Large:
/// six of them with when they were copied, and the colours copied lately, a click copies one
/// again. Clips of locked boards are never shown.
struct ClipboardWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    @ObservedObject var model: ClipboardViewModel
    let onOpen: () -> Void

    var body: some View {
        // Only as many as the widget shows: the history can be long, and this is drawn often.
        let clips = Array(model.items.lazy.filter { !$0.isEncrypted }.prefix(6))
        AraWidget(
            name: L10n.string("page.clipboard.title"), hue: .peach, onOpen: openAction(clips),
            actionName: size == .small && !clips.isEmpty ? L10n.string("widget.clipboard.paste") : nil
        ) {
            if clips.isEmpty {
                empty
            } else {
                switch size {
                case .small: small(clips[0])
                case .wide: cards(clips, count: 3, showsTime: false)
                case .large: large(clips)
                }
            }
        }
    }

    /// A small widget's click pastes the newest clip; the others open the page.
    private func openAction(_ clips: [ClipItem]) -> () -> Void {
        guard size == .small, let newest = clips.first else { return onOpen }
        return { [weak model] in model?.onPaste?(newest) }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            AraWidgetHeader(label: L10n.string("page.clipboard.title"))
            Spacer(minLength: 0)
            // No history that could be opened is not the same as nothing copied yet.
            Text(L10n.string(model.storeError == nil ? "page.overview.clipboard.empty" : "clipboard.error.title"))
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(2)
        }
    }

    private func small(_ clip: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 2 * ui) {
            AraWidgetHeader(label: L10n.string("widget.clipboard.latest"))
            Text(clip.kind == .link ? clip.linkHost : clip.snippet)
                .font(.system(size: 12 * ui, weight: .semibold))
                .lineLimit(2)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            HStack(spacing: 4 * ui) {
                Text(L10n.string("widget.clipboard.paste"))
                    .foregroundStyle(AraPalette.vivid(.peach))
                Spacer(minLength: 0)
                Text(clip.relativeTime)
                    .foregroundStyle(AraPalette.widgetSecondary)
            }
            .font(.system(size: 10.5 * ui))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private func large(_ clips: [ClipItem]) -> some View {
        let colours = ColorPalette.recent(model.items, limit: 8)
        return VStack(alignment: .leading, spacing: 6 * ui) {
            cards(clips, count: 6, showsTime: true)
            if !colours.isEmpty {
                HStack(spacing: 6 * ui) {
                    ForEach(colours) { colour in
                        let hex = ClipColor.parse(colour.text, allowingBareHex: true)?.formatted(as: .hex) ?? colour.text
                        Button {
                            model.onCopyColor?(colour, .hex)
                        } label: {
                            Circle().fill(colour.swatch)
                                .frame(width: 16 * ui, height: 16 * ui)
                                .overlay(Circle().strokeBorder(AraPalette.widgetText.opacity(0.25), lineWidth: 1))
                        }
                        .buttonStyle(AraPressStyle())
                        .help(hex)
                        .accessibilityLabel(L10n.string("overview.palette.copy"))
                        .accessibilityValue(hex)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The newest clips as cards, three to a row, under a line with how many came today.
    private func cards(_ clips: [ClipItem], count: Int, showsTime: Bool) -> some View {
        let shown = Array(clips.prefix(count))
        let today = ClipToday.count(model.items, now: Date(), calendar: .current)
        return VStack(alignment: .leading, spacing: 5 * ui) {
            AraWidgetHeader(
                label: L10n.string("widget.clipboard.today"),
                chip: today > 0 ? AraStatusChip(text: "\(today)", hue: .peach) : nil)
            ForEach(0..<(count / 3), id: \.self) { row in
                HStack(spacing: 5 * ui) {
                    ForEach(row * 3..<(row + 1) * 3, id: \.self) { index in
                        if index < shown.count {
                            WidgetClipCard(item: shown[index], thumbnail: model.thumbnail?(shown[index]), showsTime: showsTime) {
                                model.onPaste?(shown[index])
                            }
                        } else {
                            // Fewer clips than places: the cards keep their size.
                            Color.clear
                        }
                    }
                }
            }
        }
    }
}

/// One clip on the dark card: its kind's colour along the top, what it holds under it.
private struct WidgetClipCard: View {
    @Environment(\.araScale) private var ui
    let item: ClipItem
    let thumbnail: NSImage?
    let showsTime: Bool
    let action: () -> Void
    @StateObject private var hover = AraHover()

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3 * ui) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if showsTime {
                    Text(item.relativeTime)
                        .font(.system(size: 10.5 * ui))
                        .foregroundStyle(AraPalette.widgetSecondary)
                        .lineLimit(1)
                }
            }
            .padding(6 * ui)
            .background(
                RoundedRectangle(cornerRadius: 9 * ui, style: .continuous)
                    .fill(AraPalette.vivid(item.hue ?? .peach).opacity(hover.isHovered ? 0.26 : 0.16)))
            .overlay(alignment: .top) {
                Capsule().fill(AraPalette.vivid(item.hue ?? .peach))
                    .frame(height: 2 * ui)
                    .padding(.horizontal, 8 * ui)
            }
            .contentShape(RoundedRectangle(cornerRadius: 9 * ui, style: .continuous))
        }
        .buttonStyle(AraPressStyle(depth: 0.96))
        .onHover { hover.isHovered = $0 }
        .help(item.rowTitle)
        .accessibilityLabel(item.rowTitle)
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .color:
            RoundedRectangle(cornerRadius: 4 * ui).fill(item.swatch)
        case .image where thumbnail != nil:
            Color.clear
                .overlay {
                    Image(nsImage: thumbnail ?? NSImage())
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 5 * ui, style: .continuous))
        case .link:
            Text(item.linkHost)
                .font(.system(size: 10.5 * ui, weight: .semibold))
                .lineLimit(2)
        default:
            Text(item.snippet)
                .font(.system(size: 10.5 * ui))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }
}
