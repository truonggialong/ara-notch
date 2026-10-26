import AppKit
import ClipboardCore
import NotchShell
import SwiftUI

/// One history entry in the clipboard row.
struct ClipCardView: View {
    @Environment(\.araScale) private var ui
    /// Wide enough that four fill the row of the notch page.
    static let size = CGSize(width: 141, height: 104)

    let item: ClipItem
    let thumbnail: NSImage?
    /// Preview image of a link's page.
    var linkImage: NSImage?
    var isSelected = false
    var isPinned = false
    /// The pointer is over the card: it stands out before the click.
    var isHovered = false
    /// The clip was just copied with its own button: the foot of the card says so for a moment.
    var isFlashed = false
    /// When given, the foot of the card turns into the clip's quick buttons under the pointer.
    var actions: ClipboardViewModel?
    /// Takes the width of its column (the Library's grid) instead of its own.
    var fillsWidth = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            // The name the user gave the clip heads the card.
            if let title = item.title, !title.isEmpty {
                AraLabel(title)
            }
            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
        }
        .padding(8 * ui)
        .frame(width: fillsWidth ? nil : Self.size.width * ui, height: Self.size.height * ui)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        // Each kind of clip has its colour; plain text is a plain card.
        .araCard(level: isHovered ? .raised : .plate, hue: item.hue)
        .araSelectionRing(isSelected)
        .contentShape(RoundedRectangle(cornerRadius: AraTheme.cardRadius * ui, style: .continuous))
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .text:
            if CodeRecognition.isCode(item) {
                Text(CodeHighlighter.attributed(item.snippet, fontSize: 9.5 * ui))
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
            } else {
                Text(item.snippet)
                    .font(.system(size: 12 * ui))
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
        case .link:
            VStack(alignment: .leading, spacing: 3 * ui) {
                if let linkImage {
                    Color.clear
                        .overlay {
                            Image(nsImage: linkImage)
                                .resizable()
                                .scaledToFill()
                        }
                        .frame(height: 34 * ui)
                        .clipShape(RoundedRectangle(cornerRadius: 5 * ui))
                }
                if let title = item.linkTitle {
                    Text(title)
                        .font(.system(size: 10 * ui, weight: .semibold))
                        .lineLimit(linkImage == nil ? 3 : 1)
                    Label(item.linkHost, systemImage: "link")
                        .font(.system(size: 10 * ui))
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineLimit(1)
                } else {
                    Label(item.linkHost, systemImage: "link")
                        .font(.system(size: 11 * ui, weight: .semibold))
                        .lineLimit(1)
                    Text(item.snippet)
                        .font(.system(size: 10 * ui))
                        .foregroundStyle(.primary.opacity(0.55))
                        .lineLimit(2)
                }
            }
        case .color:
            VStack(alignment: .leading, spacing: 5 * ui) {
                RoundedRectangle(cornerRadius: 6 * ui)
                    .fill(item.swatch)
                    .overlay(RoundedRectangle(cornerRadius: 6 * ui).strokeBorder(AraPalette.hairline, lineWidth: 1 * ui))
                Text(item.snippet)
                    .font(.system(size: 10 * ui, design: .monospaced))
                    .lineLimit(1)
            }
        case .image:
            if let thumbnail {
                GeometryReader { area in
                    picture(thumbnail, in: area.size)
                }
            } else {
                Label(L10n.string("clipboard.image.missing"), systemImage: "photo.badge.exclamationmark")
                    .font(.system(size: 10 * ui))
                    .foregroundStyle(.primary.opacity(0.55))
            }
        case .file:
            VStack(alignment: .leading, spacing: 3 * ui) {
                Label(item.firstFileName, systemImage: "doc")
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .lineLimit(2)
                if item.filePaths.count > 1 {
                    Text(String(format: L10n.string("clipboard.files.count"), item.filePaths.count))
                        .font(.system(size: 10 * ui))
                        .foregroundStyle(.primary.opacity(0.55))
                }
            }
        }
    }

    /// The whole picture, so nothing of it is cut off; only a picture far longer or wider than
    /// the card fills it from its start instead.
    @ViewBuilder
    private func picture(_ image: NSImage, in area: CGSize) -> some View {
        switch ClipThumbnailPlacement(pictureSize: image.size, in: area) {
        case .whole:
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4 * ui))
                .frame(width: area.width, height: area.height)
        case .filledFromTop:
            filled(image, from: .top, in: area)
        case .filledFromLeading:
            filled(image, from: .leading, in: area)
        }
    }

    /// The overlay keeps the picture inside the area however large it is.
    private func filled(_ image: NSImage, from alignment: Alignment, in area: CGSize) -> some View {
        Color.clear
            .frame(width: area.width, height: area.height)
            .overlay(alignment: alignment) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6 * ui))
    }

    /// Where the clip came from and when; under the pointer, its quick buttons instead. All
    /// three are always there and only fade, so the card is never laid out again for them.
    private var footer: some View {
        ZStack {
            footerFacts
                .opacity(showsActions || isFlashed ? 0 : 1)
            if let actions {
                ClipQuickActions(item: item, model: actions)
                    .opacity(showsActions ? 1 : 0)
                    .allowsHitTesting(showsActions)
            }
            Label(L10n.string("clipboard.copied"), systemImage: "checkmark")
                .font(.system(size: 11 * ui, weight: .semibold))
                .opacity(isFlashed ? 1 : 0)
        }
        .frame(height: Self.footerHeight * ui)
    }

    private static let footerHeight: CGFloat = 22

    private var showsActions: Bool {
        isHovered && actions != nil && !isFlashed
    }

    private var footerFacts: some View {
        HStack(spacing: 4 * ui) {
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 7.5 * ui))
                    .foregroundStyle(AraPalette.label)
            }
            // The app's own icon says where the clip came from; its name is the tooltip.
            if let icon = SourceAppIcon.image(for: item.source) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13 * ui, height: 13 * ui)
                    .help(item.source.appName ?? "")
            } else {
                Text(item.source.appName ?? "")
                    .lineLimit(1)
            }
            // How heavy it is matters for a picture or a file, not for a line of text.
            if item.kind == .image || item.kind == .file {
                Text(ClipFormatters.byteCount.string(fromByteCount: Int64(item.byteSize)))
                    .lineLimit(1)
            }
            Spacer(minLength: 0 * ui)
            Text(item.relativeTime)
                .foregroundStyle(AraPalette.value)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .font(.system(size: 10 * ui, weight: .medium))
        .foregroundStyle(AraTheme.tertiaryText)
    }
}

/// The icon of the app a clip was copied from, looked up once per app.
@MainActor
enum SourceAppIcon {
    private static var cache: [String: NSImage?] = [:]

    static func image(for source: ClipSource) -> NSImage? {
        guard let bundleID = source.bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { small(NSWorkspace.shared.icon(forFile: $0.path)) }
        cache[bundleID] = icon
        return icon
    }

    /// An app's icon comes in sizes up to 1024 points. Drawn once at the few points it is
    /// shown at, it costs next to nothing each time a card is drawn again.
    private static func small(_ icon: NSImage) -> NSImage {
        let side: CGFloat = 20
        let image = NSImage(size: NSSize(width: side, height: side))
        for scale in [1, 2, 3] as [CGFloat] {
            let pixels = Int(side * scale)
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                let context = NSGraphicsContext(bitmapImageRep: rep)
            else { continue }
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(rep)
        }
        return image
    }
}

/// "Deleted · Undo": shown for the few seconds a deletion can be taken back. It is laid out
/// in a row of its own, never over the clips: a clip can be dragged, and the layer that makes
/// it so takes the clicks of anything drawn on top of it.
struct ClipUndoToast: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: ClipboardViewModel

    var body: some View {
        HStack(spacing: 8 * ui) {
            AraIcon.delete.image
                .font(.system(size: 10 * ui, weight: .semibold))
                .opacity(0.7)
            Text(model.undoableDeletionCount == 1
                ? L10n.string("clipboard.deleted.one")
                : String(format: L10n.string("clipboard.deleted.many"), model.undoableDeletionCount))
                .font(.system(size: 11 * ui, weight: .medium))
                .lineLimit(1)
            AraPillButton(L10n.string("clipboard.undo"), icon: .undo, isProminent: true) { model.onUndoDelete?() }
                .scaleEffect(0.86)
        }
        .padding(.leading, 10 * ui)
        .frame(height: 24 * ui)
        .araSurface(Capsule(), level: .raised)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}

/// The three things done most with a clip, in the foot of its card while the pointer is over
/// it: spread across the card's width, so each is easy to hit and none covers the clip.
struct ClipQuickActions: View {
    @Environment(\.araScale) private var ui
    let item: ClipItem
    @ObservedObject var model: ClipboardViewModel

    var body: some View {
        HStack(spacing: 0 * ui) {
            AraIconButton(.copy, look: .bare, size: .small) {
                // The page stays open after a copy, so the card itself says it was done.
                model.flash(item)
                model.onCopy?(item)
            }
            .frame(maxWidth: .infinity)
            if let board = model.boards.first(where: { !$0.isLocked }) {
                let isPinned = model.isPinned(item, to: board)
                AraIconButton(
                    isPinned ? .unpin : .pin, look: .bare, size: .small,
                    help: String(format: L10n.string(isPinned ? "clipboard.quick.unpin" : "clipboard.quick.pin"), board.name)
                ) {
                    model.onTogglePin?(item, board)
                }
                .frame(maxWidth: .infinity)
            }
            AraIconButton(.delete, look: .bareDanger, size: .small) { model.quickDelete(item) }
                .frame(maxWidth: .infinity)
        }
    }
}
