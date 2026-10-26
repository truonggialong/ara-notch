import AppKit
import CaptureCore
import NotchShell
import SwiftUI

/// State of one capture being annotated.
@MainActor
final class CaptureEditorModel: ObservableObject {
    let image: CGImage
    /// Points on screen per pixel of the picture.
    let displayScale: CGFloat

    @Published var document = AnnotationDocument()
    @Published var tool = AnnotationTool.arrow
    @Published var color = AnnotationColor.red
    @Published var stroke = AnnotationStroke.medium
    /// What the text tool writes.
    @Published var text = ""
    /// A short message under the toolbar, such as "Copied".
    @Published var status = ""

    var onClose: (() -> Void)?

    private var dragStart: CGPoint?
    private var dragPath: [CGPoint] = []
    private var isDrawing = false

    init(image: CGImage, displayScale: CGFloat) {
        self.image = image
        self.displayScale = displayScale
    }

    var displaySize: CGSize {
        CGSize(width: CGFloat(image.width) * displayScale, height: CGFloat(image.height) * displayScale)
    }

    /// The chosen width in points on screen, whatever the picture's scale.
    private var lineWidth: CGFloat { stroke.width / displayScale }
    /// The number a step mark being placed carries until the button comes up.
    private var stepNumber: Int?

    // MARK: - Drawing; points are in the picture's pixels

    func drag(to point: CGPoint) {
        let start = dragStart ?? point
        dragStart = start
        dragPath.append(point)
        let step = stepNumber ?? document.nextStepNumber
        stepNumber = step
        guard let shape = AnnotationDocument.shape(
            for: tool, from: start, to: point, path: dragPath, text: text, step: step)
        else { return }
        if isDrawing {
            document.replaceLast(with: shape)
        } else {
            document.add(shape, color: color, lineWidth: lineWidth)
            isDrawing = true
        }
    }

    func endDrag() {
        dragStart = nil
        dragPath = []
        isDrawing = false
        stepNumber = nil
    }

    // MARK: - Results

    var rendered: CGImage? {
        AnnotationDrawing.render(image, annotations: document.annotations)
    }

    func copyImage() {
        guard let rendered, let data = CaptureImage.pngData(rendered) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(data, forType: .png)
        onClose?()
    }

    func save() {
        guard let rendered, let data = CaptureImage.pngData(rendered) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = CaptureNaming.fileName(at: Date(), calendar: .current)
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
            onClose?()
        } catch {
            status = L10n.string("capture.status.saveFailed")
        }
    }

    /// Reads the text in the picture (without the annotations) and copies it.
    func copyText() {
        status = L10n.string("capture.status.reading")
        TextRecognizer.recognize(in: image) { [weak self] text in
            guard let self else { return }
            guard !text.isEmpty else {
                self.status = L10n.string("capture.status.noText")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let lines = text.split(separator: "\n").count
            self.status = String(format: L10n.string("capture.status.textCopied"), lines)
        }
    }
}

/// The window content for annotating a capture.
struct CaptureEditorView: View {
    @ObservedObject var model: CaptureEditorModel

    static let toolbarHeight: CGFloat = 44
    static let minimumWidth: CGFloat = 880

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .frame(height: Self.toolbarHeight)
            // A picture taller than the window (a scrolling capture) scrolls.
            ScrollView(.vertical) {
                canvas
                    .frame(width: model.displaySize.width, height: model.displaySize.height)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AraPalette.ground)
        }
        .frame(minWidth: Self.minimumWidth)
        .background(AraPalette.card)
        .araHue(.mint)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            // The tools, in one outlined bar; the one in use is filled.
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    AraIconButton(
                        Self.icon(for: tool), look: .bare, isOn: model.tool == tool,
                        help: L10n.string("capture.tool.\(tool.rawValue)")
                    ) {
                        model.tool = tool
                    }
                }
            }
            .padding(.horizontal, 3)
            .frame(height: 34)
            .araSurface(Capsule())
            if model.tool == .text {
                TextField(L10n.string("capture.text.placeholder"), text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    // Wide enough for the whole hint, in either language.
                    .frame(width: 200, height: 28)
                    .araSurface(Capsule())
            }
            HStack(spacing: 1) {
                ForEach(AnnotationColor.palette, id: \.self) { color in
                    Button {
                        model.color = color
                    } label: {
                        Circle()
                            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(AraPalette.hairline, lineWidth: 1))
                            .padding(3)
                            .overlay(Circle().strokeBorder(AraPalette.ink.opacity(model.color == color ? 1 : 0), lineWidth: 1.75))
                            .frame(width: 24, height: 26)
                            .contentShape(Rectangle())
                            .animation(AraTheme.hover, value: model.color == color)
                    }
                    .buttonStyle(AraPressStyle(depth: 0.8))
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 34)
            .araSurface(Capsule())
            // Three widths of stroke, drawn as three sizes of dot.
            HStack(spacing: 0) {
                ForEach(AnnotationStroke.allCases, id: \.self) { stroke in
                    Button {
                        model.stroke = stroke
                    } label: {
                        Circle()
                            .fill(AraPalette.ink.opacity(model.stroke == stroke ? 1 : 0.4))
                            .frame(width: stroke.width * 1.6 + 2, height: stroke.width * 1.6 + 2)
                            .frame(width: 22, height: 26)
                            .contentShape(Rectangle())
                            .animation(AraTheme.hover, value: model.stroke == stroke)
                    }
                    .buttonStyle(AraPressStyle(depth: 0.8))
                    .help(L10n.string("capture.stroke.\(stroke.rawValue)"))
                    .accessibilityLabel(L10n.string("capture.stroke.\(stroke.rawValue)"))
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 34)
            .araSurface(Capsule())
            HStack(spacing: 2) {
                AraIconButton(.undo, look: .bare, help: L10n.string("capture.undo")) { model.document.undo() }
                    .disabled(!model.document.canUndo)
                    .opacity(model.document.canUndo ? 1 : 0.35)
                AraIconButton(.redo, look: .bare, help: L10n.string("capture.redo")) { model.document.redo() }
                    .disabled(!model.document.canRedo)
                    .opacity(model.document.canRedo ? 1 : 0.35)
            }
            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(AraTheme.secondaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            // What to do with the picture: icons, with the usual one filled and on Return.
            HStack(spacing: 6) {
                AraIconButton(.readText, help: L10n.string("capture.copyText")) { model.copyText() }
                AraIconButton(.save, help: L10n.string("capture.save")) { model.save() }
                AraIconButton(.copy, look: .accent, help: L10n.string("capture.copy")) { model.copyImage() }
                    .keyboardShortcut(.defaultAction)
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .foregroundStyle(AraPalette.ink)
    }

    /// The picture with the annotations over it; a drag draws with the current tool.
    private var canvas: some View {
        let scale = model.displayScale
        return Canvas { context, size in
            context.draw(
                Image(decorative: model.image, scale: 1), in: CGRect(origin: .zero, size: size))
            context.withCGContext { cgContext in
                cgContext.scaleBy(x: scale, y: scale)
                AnnotationDrawing.draw(model.document.annotations, over: model.image, in: cgContext)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    model.drag(to: CGPoint(x: value.location.x / scale, y: value.location.y / scale))
                }
                .onEnded { _ in model.endDrag() }
        )
    }

    private static func icon(for tool: AnnotationTool) -> AraIcon {
        switch tool {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .step: .step
        case .blur: .blur
        case .highlight: .highlight
        case .pen: .draw
        case .text: .typeText
        }
    }
}
