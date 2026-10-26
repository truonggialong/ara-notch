import AppKit
import ClipboardCore
import NotchShell
import SwiftUI
import UniformTypeIdentifiers

/// Dragging clips: out to other apps as their content, and inside the app by identity, to pin
/// a clip to a board or to reorder a board.
@MainActor
enum ClipDrag {
    /// Carries the dragged clip's id; declared in Info.plist and visible to this app only.
    static let clipIDType = "com.aranotch.clip-id"

    /// What a drag of this clip carries: its content for other apps, its id for this one.
    static func provider(for item: ClipItem, model: ClipboardViewModel) -> NSItemProvider {
        provider(for: [item], model: model)
    }

    /// A drag of several clips at once. Other apps receive their text joined line by line (or
    /// the first clip alone when none has text); this app receives every id.
    static func provider(for items: [ClipItem], model: ClipboardViewModel) -> NSItemProvider {
        guard let first = items.first else { return NSItemProvider() }
        let provider: NSItemProvider
        let texts = items.filter { $0.kind == .text || $0.kind == .link || $0.kind == .color }.map(\.text)
        if items.count > 1, !texts.isEmpty {
            provider = NSItemProvider(object: texts.joined(separator: "\n") as NSString)
            provider.suggestedName = first.rowTitle
        } else {
            provider = contentProvider(for: first, model: model)
        }
        let ids = Data(ClipMultiSelection.encode(items.map(\.id)).utf8)
        provider.registerDataRepresentation(forTypeIdentifier: clipIDType, visibility: .ownProcess) { completion in
            completion(ids, nil)
            return nil
        }
        return provider
    }

    private static func contentProvider(for item: ClipItem, model: ClipboardViewModel) -> NSItemProvider {
        let provider: NSItemProvider
        switch item.kind {
        case .link:
            if let url = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                provider = NSItemProvider(object: url as NSURL)
                provider.registerObject(item.text as NSString, visibility: .all)
            } else {
                provider = NSItemProvider(object: item.text as NSString)
            }
        case .text, .color:
            provider = NSItemProvider(object: item.text as NSString)
        case .image:
            provider = NSItemProvider()
            if let data = model.imageData?(item) {
                let type = ClipImageData.typeIdentifier(of: data) ?? UTType.png.identifier
                provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) {
                    completion in
                    completion(data, nil)
                    return nil
                }
            }
        case .file:
            // One provider carries one file; the first one stands for the clip. It travels as a
            // file URL, which is what Finder and other apps expect of a dragged file.
            provider = item.filePaths.first.map { NSItemProvider(object: URL(fileURLWithPath: $0) as NSURL) }
                ?? NSItemProvider()
        }
        provider.suggestedName = item.rowTitle
        return provider
    }

    /// Reads the clip ids out of a drop and hands them over, one by one, on the main actor. Returns false when
    /// the drop carries no clip of this app.
    static func handleDrop(_ providers: [NSItemProvider], _ action: @escaping @MainActor (Int64) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(clipIDType) }) else {
            return false
        }
        _ = provider.loadDataRepresentation(forTypeIdentifier: clipIDType) { data, _ in
            guard let data else { return }
            let ids = ClipMultiSelection.decode(String(decoding: data, as: UTF8.self))
            // A drag may carry several clips; each one is handed over in turn.
            Task { @MainActor in ids.forEach(action) }
        }
        return true
    }
}

extension View {
    /// Makes the view draggable as this clip.
    @MainActor
    func draggable(as item: ClipItem, model: ClipboardViewModel) -> some View {
        onDrag { ClipDrag.provider(for: item, model: model) }
    }

    /// Accepts clips dragged from inside the app.
    @MainActor
    func onClipDrop(_ action: @escaping @MainActor (Int64) -> Void) -> some View {
        onDrop(of: [ClipDrag.clipIDType], isTargeted: nil) { providers in
            ClipDrag.handleDrop(providers, action)
        }
    }
}

/// A place clips can be dropped on. It is told while one is held over it, so it can light up.
struct ClipDropTarget<Content: View>: View {
    let action: @MainActor (Int64) -> Void
    let content: (_ isTargeted: Bool) -> Content
    @StateObject private var target = AraHover()

    init(action: @escaping @MainActor (Int64) -> Void, @ViewBuilder content: @escaping (_ isTargeted: Bool) -> Content) {
        self.action = action
        self.content = content
    }

    var body: some View {
        content(target.isHovered)
            .onDrop(of: [ClipDrag.clipIDType], isTargeted: $target.isHovered) { providers in
                ClipDrag.handleDrop(providers, action)
            }
    }
}
