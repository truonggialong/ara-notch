import AppKit
import Combine
import FilesCore
import NotchShell
import SwiftUI
import UniformTypeIdentifiers

/// State the Files page renders from.
@MainActor
final class FilesViewModel: ObservableObject {
    /// The files dropped on the notch, in drop order.
    @Published var files: [URL] = []
    /// What the last action made.
    @Published var results: [URL] = []
    /// Localized outcome of the last action.
    @Published var message: String?
    @Published var isBusy = false
    /// How many of the files the running action has finished, and how many it has to do.
    @Published var doneCount = 0
    @Published var totalCount = 0

    /// Shows the page as it is while files are dragged over it, for automated checks.
    @Published var showsDropTargets = false

    var onDrop: (([URL]) -> Void)?
    /// Files let go over an action's tile: add them, then do that action.
    var onDropOnTile: (([URL], FileDropTile) -> Void)?
    var onRemove: ((URL) -> Void)?
    var onClear: (() -> Void)?
    var onAction: ((FileAction) -> Void)?
    var onAirDrop: (() -> Void)?
    var onReveal: (() -> Void)?
}

/// The Files page: files dropped on the notch can be converted, resized, compressed, combined
/// into a PDF or sent by AirDrop. Results are new files next to the originals.
@MainActor
public final class FilesController {
    private let viewModel = FilesViewModel()
    private var dragWatch: Timer?

    public init() {
        viewModel.onDrop = { [weak self] urls in
            AraHaptics.play(.tap)
            self?.add(urls)
        }
        viewModel.onDropOnTile = { [weak self] urls, tile in
            guard let self else { return }
            AraHaptics.play(.tap)
            self.add(urls)
            if let action = tile.action {
                // Not every file can take every action; then the files are just kept.
                self.run(action)
            } else {
                self.airDrop()
            }
        }
        viewModel.onRemove = { [weak self] url in self?.viewModel.files.removeAll { $0 == url } }
        viewModel.onClear = { [weak self] in self?.clear() }
        viewModel.onAction = { [weak self] action in self?.run(action) }
        viewModel.onAirDrop = { [weak self] in self?.airDrop() }
        viewModel.onReveal = { [weak self] in
            guard let results = self?.viewModel.results, !results.isEmpty else { return }
            NSWorkspace.shared.activateFileViewerSelecting(results)
        }
    }

    public func makePage() -> NotchPage {
        NotchPage(
            id: "files", titleKey: "page.files.title", symbolName: "tray.and.arrow.down", hue: .sage
        ) { [viewModel] in
            FilesPageView(model: viewModel)
        }
    }

    /// Adds files as if they had been dropped on the page. Folders and duplicates are skipped.
    /// Shows the page as it is while files are dragged over it, for automated checks.
    public func showDropTargets() {
        viewModel.showsDropTargets = true
    }

    /// Files are on their way: the page shows where they can be dropped at once, without
    /// waiting for the pointer to move over it again, until the mouse button is let go.
    public func filesAreBeingDragged() {
        viewModel.showsDropTargets = true
        dragWatch?.invalidate()
        let watch = Timer(timeInterval: 0.1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self?.viewModel.showsDropTargets = false
                self?.dragWatch?.invalidate()
                self?.dragWatch = nil
            }
        }
        // Common modes: a drag runs the run loop in event-tracking mode.
        RunLoop.main.add(watch, forMode: .common)
        dragWatch = watch
    }

    public func add(_ urls: [URL]) {
        for url in urls where !viewModel.files.contains(url) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                continue
            }
            viewModel.files.append(url)
        }
        viewModel.results = []
        viewModel.message = nil
    }

    /// Runs the action with this name on the dropped files, as its button would:
    /// `convert-png`, `convert-jpeg`, `convert-heic`, `resize-50`, `resize-25`, `compress`, `pdf`.
    public func run(actionNamed name: String) {
        let actions: [String: FileAction] = [
            "convert-png": .convert(.png), "convert-jpeg": .convert(.jpeg), "convert-heic": .convert(.heic),
            "resize-50": .resize(percent: 50), "resize-25": .resize(percent: 25), "compress": .compress, "pdf": .makePDF,
        ]
        if let action = actions[name] {
            run(action)
        }
    }

    private func clear() {
        viewModel.files = []
        viewModel.results = []
        viewModel.message = nil
    }

    private func run(_ action: FileAction) {
        let files = viewModel.files
        guard !viewModel.isBusy, FileActions.available(for: files).contains(action) else { return }
        viewModel.isBusy = true
        viewModel.message = nil
        viewModel.results = []
        viewModel.doneCount = 0
        viewModel.totalCount = action == .makePDF ? 1 : files.count
        // Large images take a moment; the work stays off the main thread.
        Task.detached(priority: .userInitiated) { [weak self] in
            var results: [URL] = []
            var failures = 0
            var unchanged = 0
            if action == .makePDF {
                do {
                    results.append(try FileActions.makePDF(from: files))
                } catch {
                    failures = files.count
                }
            } else {
                for file in files {
                    do {
                        if let result = try FileActions.run(action, on: file) {
                            results.append(result)
                        } else {
                            unchanged += 1
                        }
                    } catch {
                        failures += 1
                    }
                    await self?.advanced(to: results.count + failures + unchanged)
                }
            }
            await self?.finished(results: results, failures: failures, unchanged: unchanged)
        }
    }

    private func advanced(to count: Int) {
        viewModel.doneCount = count
    }

    private func finished(results: [URL], failures: Int, unchanged: Int) {
        viewModel.isBusy = false
        viewModel.doneCount = viewModel.totalCount
        AraHaptics.play(failures > 0 ? .change : .tap)
        viewModel.results = results
        if failures > 0 {
            NSSound.beep()
            viewModel.message = String(format: L10n.string("page.files.failed"), results.count, failures)
        } else if unchanged > 0 {
            viewModel.message = String(format: L10n.string("page.files.unchanged"), results.count, unchanged)
        } else {
            viewModel.message = String(format: L10n.string("page.files.done"), results.count)
        }
    }

    private func airDrop() {
        let files = viewModel.files
        guard !files.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: files) else {
            NSSound.beep()
            viewModel.message = L10n.string("page.files.airdrop.unavailable")
            return
        }
        service.perform(withItems: files)
    }
}

/// The Files page of the notch: the dropped files fanned out behind a paper folder, and a bar
/// of icons for what can be done with them.
struct FilesPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: FilesViewModel
    /// Whether files are being dragged over the page, and how many.
    @StateObject private var dropTarget = FileDragState()
    /// True while they are over one of the action tiles, one object per tile.
    @StateObject private var airDropTile = AraHover()
    @StateObject private var resizeTile = AraHover()
    @StateObject private var compressTile = AraHover()
    @StateObject private var pdfTile = AraHover()

    private func hover(of tile: FileDropTile) -> AraHover {
        switch tile {
        case .airDrop: airDropTile
        case .resize: resizeTile
        case .compress: compressTile
        case .pdf: pdfTile
        }
    }

    /// Files are in the air over the page or over one of its tiles.
    private var isDragging: Bool {
        model.showsDropTargets || dropTarget.isOver || FileDropTile.allCases.contains { hover(of: $0).isHovered }
    }

    var body: some View {
        Group {
            if model.files.isEmpty {
                AraEmptyState(icon: .files, title: L10n.string("page.files.empty.title"), detail: L10n.string("page.files.empty"))
            } else {
                HStack(spacing: 18 * ui) {
                    // Once an action has made files, the cards are those: they can be dragged
                    // straight out to wherever they are needed.
                    FileFan(files: model.results.isEmpty ? model.files : model.results, areResults: !model.results.isEmpty)
                        .frame(width: 170 * ui)
                        .padding(.leading, 12 * ui)
                    VStack(alignment: .leading, spacing: 8 * ui) {
                        fileRow
                        actionRow
                        statusRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4 * ui)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onDrop(of: Self.dropTypes, delegate: FilePageDrop(state: dropTarget) { providers in
            Self.loadURLs(from: providers) { urls in model.onDrop?(urls) }
        })
        // While files are in the air the page turns into places to drop them: most of it to
        // keep them here, which is what a drop is usually for, and a narrow column of
        // actions for doing something with them at once.
        .overlay {
            dropTiles
                .opacity(isDragging ? 1 : 0)
                .allowsHitTesting(isDragging)
                .animation(AraTheme.hover, value: isDragging)
        }
    }

    private static let dropTypes = [UTType.fileURL.identifier, UTType.item.identifier]

    private var dropTiles: some View {
        HStack(spacing: 10 * ui) {
            keepZone
            VStack(spacing: 5 * ui) {
                ForEach(FileDropTile.allCases, id: \.self) { tile in
                    dropTile(tile)
                }
            }
            .frame(width: 132 * ui)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Opaque: what the page showed before must not read through.
        .background(AraPalette.ground)
    }

    /// Where a drop only keeps the files: the large part of the page, lit while the files
    /// are over it and not over an action.
    private var keepZone: some View {
        let isOverAction = FileDropTile.allCases.contains { hover(of: $0).isHovered }
        let isLit = dropTarget.isOver && !isOverAction
        let shape = RoundedRectangle(cornerRadius: AraTheme.cardRadius * ui, style: .continuous)
        return VStack(spacing: 4 * ui) {
            AraIcon.files.image
                .font(.system(size: 20 * ui, weight: .medium))
                .foregroundStyle(AraPalette.tint(.sage).line)
            Text(L10n.string("page.files.drop.keep"))
                .font(.system(size: 13 * ui, weight: .semibold))
            if dropTarget.count > 0 {
                Text(dropTarget.count == 1
                    ? L10n.string("page.files.drop.count.one")
                    : String(format: L10n.string("page.files.drop.count"), dropTarget.count))
                    .font(.system(size: 11 * ui))
                    .opacity(0.68)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isLit ? AraPalette.hoverWash : .clear, in: shape)
        .overlay {
            shape.strokeBorder(
                AraPalette.tint(.sage).line.opacity(isLit ? 1 : 0.45),
                style: StrokeStyle(lineWidth: 1.5 * ui, dash: [5, 4]))
        }
        .animation(AraTheme.hover, value: isLit)
    }

    /// One action as a place to drop: a small row, so that keeping stays the main thing.
    private func dropTile(_ tile: FileDropTile) -> some View {
        let hover = hover(of: tile)
        return HStack(spacing: 7 * ui) {
            Self.icon(for: tile).image
                .font(.system(size: 12 * ui, weight: .medium))
                .frame(width: 16 * ui)
            Text(Self.icon(for: tile).label)
                .font(.system(size: 11 * ui, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0 * ui)
        }
        .padding(.horizontal, 10 * ui)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .araCard(radius: AraTheme.rowRadius, level: hover.isHovered ? .selected : .raised)
        .animation(AraTheme.hover, value: hover.isHovered)
        .onDrop(of: Self.dropTypes, isTargeted: Binding(
            get: { hover.isHovered }, set: { hover.isHovered = $0 })
        ) { providers in
            Self.loadURLs(from: providers) { urls in model.onDropOnTile?(urls, tile) }
            return true
        }
    }

    private static func icon(for tile: FileDropTile) -> AraIcon {
        switch tile {
        case .airDrop: .airDrop
        case .resize: .resize
        case .compress: .compress
        case .pdf: .pdf
        }
    }

    private var fileRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5 * ui) {
                ForEach(model.files, id: \.self) { file in
                    HStack(spacing: 5 * ui) {
                        (FileActions.isImage(file) ? AraIcon.picture : AraIcon.document).image
                            .font(.system(size: 10 * ui, weight: .medium))
                        Text(file.lastPathComponent)
                            .font(.system(size: 11 * ui))
                            .lineLimit(1)
                        Button {
                            model.onRemove?(file)
                        } label: {
                            AraIcon.close.image
                                .font(.system(size: 7.5 * ui, weight: .bold))
                                .foregroundStyle(AraPalette.ink.opacity(0.55))
                                .frame(width: 14 * ui, height: 14 * ui)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(AraPressStyle(depth: 0.8))
                        .help(AraIcon.remove.label)
                    }
                    .padding(.leading, 9 * ui)
                    .padding(.trailing, 5 * ui)
                    .frame(height: 24 * ui)
                    .frame(maxWidth: 170 * ui)
                    .araSurface(Capsule())
                }
            }
            .padding(.vertical, 1 * ui)
        }
    }

    /// Every action is an icon; its name is in its tooltip.
    private var actionRow: some View {
        let actions = FileActions.available(for: model.files)
        let conversions = actions.compactMap { action -> ImageFormat? in
            if case .convert(let format) = action { return format }
            return nil
        }
        return HStack(spacing: 4 * ui) {
            if !conversions.isEmpty {
                iconMenu(.convert) {
                    ForEach(conversions, id: \.self) { format in
                        Button(format.rawValue.uppercased()) { model.onAction?(.convert(format)) }
                    }
                }
                iconMenu(.resize) {
                    Button("50%") { model.onAction?(.resize(percent: 50)) }
                    Button("25%") { model.onAction?(.resize(percent: 25)) }
                }
                AraIconButton(.compress, look: .bare) { model.onAction?(.compress) }
                AraIconButton(.pdf, look: .bare) { model.onAction?(.makePDF) }
            }
            AraIconButton(.airDrop, look: .bare) { model.onAirDrop?() }
            AraIconButton(.preview, look: .bare, help: L10n.string("page.files.preview")) {
                AraQuickLook.shared.toggle(model.results.isEmpty ? model.files : model.results)
            }
            Spacer(minLength: 0 * ui)
            AraIconButton(.delete, look: .danger, help: L10n.string("page.files.clear")) { model.onClear?() }
        }
        .padding(.horizontal, 6 * ui)
        .frame(height: 38 * ui)
        .araSurface(Capsule())
        .disabled(model.isBusy)
        .opacity(model.isBusy ? 0.5 : 1)
        .animation(AraTheme.hover, value: model.isBusy)
    }

    private func iconMenu<Items: View>(_ icon: AraIcon, @ViewBuilder items: () -> Items) -> some View {
        Menu {
            items()
        } label: {
            AraIconFace(icon: icon, look: .bare)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(icon.label)
        .accessibilityLabel(icon.label)
    }

    private var statusRow: some View {
        HStack(spacing: 8 * ui) {
            if model.isBusy, model.totalCount > 0 {
                // One step per file, so a long batch shows how far it has got.
                AraProgressRing(fraction: Double(model.doneCount) / Double(model.totalCount), lineWidth: 2.6)
                    .frame(width: 20 * ui, height: 20 * ui)
                    .animation(AraTheme.settle, value: model.doneCount)
                Text("\(FileProgress.percent(done: model.doneCount, total: model.totalCount))%")
                    .font(.system(size: 12 * ui, weight: .bold))
                    .monospacedDigit()
                Text("\(model.doneCount)/\(model.totalCount)")
                    .font(.system(size: 10 * ui, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AraTheme.secondaryText)
            }
            if let message = model.message {
                Text(message)
                    .font(.system(size: 11 * ui))
                    .foregroundStyle(AraTheme.secondaryText)
                    .lineLimit(1)
            }
            if !model.results.isEmpty {
                AraIconButton(.reveal, size: .small) { model.onReveal?() }
            }
        }
        .frame(height: 22 * ui)
    }

    /// Collects the file URLs of a drop, then reports them once on the main actor.
    private static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let collected = Collected()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    if let data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        collected.append(url)
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                // Some sources offer the file itself rather than its URL. Only a file that can
                // be used where it is counts; a temporary copy would be gone after this call.
                group.enter()
                _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, isInPlace, _ in
                    if let url, isInPlace {
                        collected.append(url)
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            let urls = collected.urls
            MainActor.assumeIsolated { completion(urls) }
        }
    }

    /// URLs gathered from several loader callbacks, which may run on different threads.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URL] = []

        func append(_ url: URL) {
            lock.lock()
            storage.append(url)
            lock.unlock()
        }

        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}

/// What is being dragged over the Files page.
@MainActor
final class FileDragState: ObservableObject {
    @Published var isOver = false
    /// How many things are in the air; zero when it is not known.
    @Published var count = 0
}

/// Follows a drag over the Files page: that it is there, how many files it carries, and
/// the drop itself.
private struct FilePageDrop: DropDelegate {
    let state: FileDragState
    let onDrop: ([NSItemProvider]) -> Void

    private static let types = [UTType.fileURL.identifier, UTType.item.identifier]

    func dropEntered(info: DropInfo) {
        state.count = info.itemProviders(for: Self.types).count
        state.isOver = true
    }

    func dropExited(info: DropInfo) {
        state.isOver = false
    }

    func performDrop(info: DropInfo) -> Bool {
        state.isOver = false
        onDrop(info.itemProviders(for: Self.types))
        return true
    }
}

/// The first few dropped files as cards fanned out, with a paper folder in front that says
/// how many there are.
private struct FileFan: View {
    @Environment(\.araScale) private var ui
    let files: [URL]
    /// The cards are files an action just made; they carry a tick and can be dragged out.
    var areResults = false

    private static let angles: [[Double]] = [[0], [-8, 8], [-13, 0, 13]]
    private static let offsets: [[CGFloat]] = [[0], [-22, 22], [-36, 0, 36]]

    var body: some View {
        let shown = Array(files.prefix(3))
        ZStack(alignment: .bottom) {
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.element) { index, file in
                    card(for: file)
                        .rotationEffect(.degrees(Self.angles[shown.count - 1][index]))
                        .offset(x: Self.offsets[shown.count - 1][index], y: shown.count == 3 && index != 1 ? 8 : 0)
                        .zIndex(index == shown.count / 2 ? 1 : 0)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 2 * ui)
            folder
        }
        .animation(AraTheme.settle, value: files)
    }

    private func card(for file: URL) -> some View {
        AraPalette.sheet
            .overlay {
                Image(nsImage: FileThumbnails.image(for: file))
                    .resizable()
                    .scaledToFill()
                    .padding(FileActions.isImage(file) ? 0 : 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8 * ui, style: .continuous))
            .padding(4 * ui)
            .background(AraPalette.sheet, in: RoundedRectangle(cornerRadius: 11 * ui, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11 * ui, style: .continuous)
                    .strokeBorder(AraPalette.hairline, lineWidth: 1 * ui)
            }
            .frame(width: 72 * ui, height: 92 * ui)
            .overlay(alignment: .topTrailing) {
                if areResults {
                    AraIcon.completed.image
                        .font(.system(size: 13 * ui))
                        .foregroundStyle(AraPalette.ground, AraPalette.value)
                        .offset(x: 4 * ui, y: -4)
                }
            }
            .onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }
    }

    private var folder: some View {
        VStack(alignment: .leading, spacing: 1 * ui) {
            ForEach(files.prefix(2), id: \.self) { file in
                Text(file.lastPathComponent)
                    .font(.system(size: 11 * ui, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text((files.count == 1 ? L10n.string("page.files.drop.count.one") : String(format: L10n.string("page.files.drop.count"), files.count)))
                .font(.system(size: 10 * ui))
                .foregroundStyle(AraTheme.secondaryText)
        }
        .padding(.horizontal, 12 * ui)
        .padding(.top, 18 * ui)
        .padding(.bottom, 9 * ui)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                // Solid: the cards stand in the folder, their lower halves behind it.
                FolderShape().fill(AraPalette.well)
            }
        }
        .zIndex(2)
    }
}

/// A folder seen from the front: a rounded plate with a tab on its top left.
private struct FolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 12
        let tabHeight: CGFloat = 10
        let tabWidth = rect.width * 0.42
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + tabWidth - 8, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX + tabWidth + 14, y: rect.minY + tabHeight),
            control1: CGPoint(x: rect.minX + tabWidth + 2, y: rect.minY),
            control2: CGPoint(x: rect.minX + tabWidth + 4, y: rect.minY + tabHeight))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY + tabHeight))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + tabHeight + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY + tabHeight))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A small picture of a file for its card: the picture itself, or the file's icon.
@MainActor
private enum FileThumbnails {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for file: URL) -> NSImage {
        if let cached = cache.object(forKey: file as NSURL) { return cached }
        let image = (FileActions.isImage(file) ? NSImage(contentsOf: file) : nil)
            ?? NSWorkspace.shared.icon(forFile: file.path)
        cache.setObject(image, forKey: file as NSURL)
        return image
    }
}
