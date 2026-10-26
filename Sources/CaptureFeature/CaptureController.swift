import AppKit
import CaptureCore
import Combine
import NotchShell
import SwiftUI

/// Observable capture settings; every change is written through to the store.
@MainActor
public final class CaptureSettings: ObservableObject {
    private let store: CaptureSettingsStore

    @Published public var shortcutEnabled: Bool {
        didSet { store.shortcutEnabled = shortcutEnabled }
    }

    /// macOS lets this app see other apps' windows.
    @Published var hasPermission = false

    var onCapture: (() -> Void)?
    var onScrollCapture: (() -> Void)?
    var onCaptureText: (() -> Void)?
    var onPickColor: (() -> Void)?
    var onOpenPrivacySettings: (() -> Void)?

    public init(store: CaptureSettingsStore) {
        self.store = store
        shortcutEnabled = store.shortcutEnabled
    }
}

/// Screen capture: the user drags out a region, the picture opens in a window where it can be
/// drawn on, copied, saved, or have its text read. Nothing leaves this Mac.
@MainActor
public final class CaptureController {
    /// The editor never opens larger than this.
    private static let maximumDisplaySize = CGSize(width: 1100, height: 640)

    private let settings: CaptureSettings
    private let shortcuts: ShortcutCenter
    private var cancellables = Set<AnyCancellable>()
    /// Open editor windows, kept alive until they close.
    private var editors: [NSWindow: NSObjectProtocol] = [:]
    private var isCapturing = false
    private let pasteboard: NSPasteboard
    /// Kept while the system's colour loupe is on screen.
    private var colorSampler: NSColorSampler?

    /// Told what happened after copying text or a colour from the screen: a symbol name and a
    /// short message, for a notice beside the notch.
    public var onNotice: ((_ symbol: String, _ message: String) -> Void)?
    private let regionSelector = RegionSelector()
    private var scrollSession: ScrollCaptureSession?

    public init(settings: CaptureSettings, shortcuts: ShortcutCenter, pasteboard: NSPasteboard = .general) {
        self.settings = settings
        self.shortcuts = shortcuts
        self.pasteboard = pasteboard
        settings.onCapture = { [weak self] in self?.capture() }
        settings.onScrollCapture = { [weak self] in self?.captureScrolling() }
        settings.onCaptureText = { [weak self] in self?.captureText() }
        settings.onPickColor = { [weak self] in self?.pickColor() }
        settings.onOpenPrivacySettings = {
            let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            if let url = URL(string: pane) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    public func start() {
        settings.hasPermission = ScreenCapturer.hasPermission
        shortcuts.setHandler(.captureRegion) { [weak self] in self?.capture() }
        shortcuts.setHandler(.captureScrolling) { [weak self] in self?.captureScrolling() }
        shortcuts.setHandler(.captureText) { [weak self] in self?.captureText() }
        shortcuts.setHandler(.pickColor) { [weak self] in self?.pickColor() }
        settings.$shortcutEnabled
            .sink { [weak self] isEnabled in self?.shortcuts.setEnabled(isEnabled, for: .captureRegion) }
            .store(in: &cancellables)
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(CaptureSettingsSection(settings: settings, shortcuts: shortcuts))
    }

    /// Lets the user pick a region of the screen, then opens it for annotating.
    public func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        ScreenCapturer.captureRegion { [weak self] image in
            guard let self else { return }
            self.isCapturing = false
            self.settings.hasPermission = ScreenCapturer.hasPermission
            if let image {
                self.openEditor(for: image)
            }
        }
    }

    /// Lets the user pick a region of the screen and copies the text in it, without opening
    /// the editor. The text is read on this Mac.
    public func captureText() {
        guard !isCapturing else { return }
        isCapturing = true
        ScreenCapturer.captureRegion { [weak self] image in
            guard let self else { return }
            self.isCapturing = false
            self.settings.hasPermission = ScreenCapturer.hasPermission
            guard let image else { return }
            self.onNotice?("text.viewfinder", L10n.string("capture.status.reading"))
            TextRecognizer.recognize(in: image) { [weak self] text in
                self?.finishCaptureText(text)
            }
        }
    }

    private func finishCaptureText(_ text: String) {
        guard !text.isEmpty else {
            NSSound.beep()
            onNotice?("text.viewfinder", L10n.string("capture.notice.noText"))
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let lines = text.split(separator: "\n").count
        onNotice?("text.viewfinder", String(format: L10n.string("capture.notice.textCopied"), lines))
    }

    /// Shows the system's colour loupe and copies the colour picked with it as "#RRGGBB".
    public func pickColor() {
        guard colorSampler == nil else { return }
        let sampler = NSColorSampler()
        colorSampler = sampler
        sampler.show { [weak self] color in
            // The loupe answers on the main thread; nil when the user pressed Escape.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.colorSampler = nil
                guard let color = color?.usingColorSpace(.sRGB) else { return }
                let hex = ScreenColor.hex(
                    red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
                self.pasteboard.clearContents()
                self.pasteboard.setString(hex, forType: .string)
                self.onNotice?("eyedropper", hex)
            }
        }
    }

    /// Cuts the subject of a picture out of its background, for other parts of the app. Answers
    /// on the main actor with PNG data, or nil when no subject was found.
    public func cutOutSubject(fromImageData data: Data, completion: @escaping @MainActor (Data?) -> Void) {
        SubjectCutout.cutOut(from: data, completion: completion)
    }

    /// Reads the text in picture data, for other parts of the app. Answers on the main actor;
    /// empty when the data is not a picture or holds no text.
    public func recognizeText(inImageData data: Data, completion: @escaping @MainActor (String) -> Void) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            completion("")
            return
        }
        TextRecognizer.recognize(in: image, completion: completion)
    }

    /// Lets the user drag out a region over a page, then scrolls that page and joins what
    /// passes through the region into one tall picture.
    public func captureScrolling() {
        guard !isCapturing else { return }
        isCapturing = true
        regionSelector.select { [weak self] rect in
            guard let self else { return }
            guard let rect else {
                self.isCapturing = false
                return
            }
            // A moment for the dimmed overlay to leave the screen before the first frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.captureScrolling(in: rect)
            }
        }
    }

    /// Scrolls and captures a fixed rectangle (global coordinates, origin top left).
    /// - Parameter framesDirectory: for automated checks, where every frame is also written.
    public func captureScrolling(in rect: CGRect, framesDirectory: URL? = nil) {
        ScrollCaptureSession.framesDirectory = framesDirectory
        isCapturing = true
        let session = ScrollCaptureSession(rect: rect) { [weak self] image in
            guard let self else { return }
            self.scrollSession = nil
            self.isCapturing = false
            self.settings.hasPermission = ScreenCapturer.hasPermission
            if let image {
                self.openEditor(for: image)
            }
        }
        scrollSession = session
        session.start()
    }

    /// Captures a fixed rectangle of the screen and opens it for annotating; for automated checks.
    public func capture(rect: CGRect) {
        ScreenCapturer.capture(rect: rect) { [weak self] image in
            if let image {
                self?.openEditor(for: image)
            }
        }
    }

    /// Opens a picture file in the editor, as a capture would.
    @discardableResult
    public func openEditor(forImageAt file: URL) -> Bool {
        guard let image = CaptureImage.load(file) else { return false }
        openEditor(for: image)
        return true
    }

    /// Reads the text in a picture file and writes it to another file; for automated checks.
    public func recognizeText(inImageAt file: URL, writingTo output: URL) {
        guard let image = CaptureImage.load(file) else { return }
        TextRecognizer.recognize(in: image) { text in
            try? text.write(to: output, atomically: true, encoding: .utf8)
        }
    }

    /// Draws a fixed set of annotations into a picture file and writes the result; for automated checks.
    public func renderSample(ontoImageAt file: URL, writingTo output: URL) {
        guard let image = CaptureImage.load(file) else { return }
        var document = AnnotationDocument()
        let width = CGFloat(image.width), height = CGFloat(image.height)
        document.add(.rectangle(CGRect(x: width * 0.1, y: height * 0.1, width: width * 0.3, height: height * 0.3)), color: .red, lineWidth: 6)
        document.add(.arrow(from: CGPoint(x: width * 0.9, y: height * 0.9), to: CGPoint(x: width * 0.5, y: height * 0.5)), color: .blue, lineWidth: 6)
        document.add(.highlight(CGRect(x: width * 0.5, y: height * 0.1, width: width * 0.4, height: height * 0.15)), color: .yellow, lineWidth: 6)
        document.add(.text("AraNotch", at: CGPoint(x: width * 0.1, y: height * 0.75)), color: .green, lineWidth: 6)
        document.add(.ellipse(CGRect(x: width * 0.55, y: height * 0.3, width: width * 0.3, height: height * 0.2)), color: .white, lineWidth: 6)
        document.add(.line(from: CGPoint(x: width * 0.1, y: height * 0.9), to: CGPoint(x: width * 0.45, y: height * 0.9)), color: .yellow, lineWidth: 10)
        document.add(.blur(CGRect(x: width * 0.3, y: height * 0.45, width: width * 0.4, height: height * 0.22)), color: .red, lineWidth: 6)
        document.add(.step(1, at: CGPoint(x: width * 0.2, y: height * 0.55)), color: .red, lineWidth: 6)
        document.add(.step(2, at: CGPoint(x: width * 0.8, y: height * 0.7)), color: .yellow, lineWidth: 6)
        guard let rendered = AnnotationDrawing.render(image, annotations: document.annotations),
              let data = CaptureImage.pngData(rendered) else { return }
        try? data.write(to: output)
    }

    private func openEditor(for image: CGImage) {
        // A capture of a Retina display has two pixels per point; then shrink to fit if needed.
        let backing = NSScreen.main?.backingScaleFactor ?? 2
        let natural = CGSize(width: CGFloat(image.width) / backing, height: CGFloat(image.height) / backing)
        // A tall picture (a scrolling capture) keeps its width and scrolls; others shrink to fit.
        let isTall = natural.height > natural.width * 1.5
        let fit = isTall
            ? min(1, Self.maximumDisplaySize.width / natural.width)
            : min(1, Self.maximumDisplaySize.width / natural.width, Self.maximumDisplaySize.height / natural.height)
        let model = CaptureEditorModel(image: image, displayScale: fit / backing)

        let hosting = NSHostingController(rootView: CaptureEditorView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = L10n.string("capture.window.title")
        window.isReleasedWhenClosed = false
        window.setContentSize(CGSize(
            width: max(model.displaySize.width, CaptureEditorView.minimumWidth),
            height: min(model.displaySize.height, Self.maximumDisplaySize.height) + CaptureEditorView.toolbarHeight))
        window.center()
        model.onClose = { [weak window] in window?.close() }

        editors[window] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, let observer = self.editors.removeValue(forKey: window) else { return }
                NotificationCenter.default.removeObserver(observer)
            }
        }
        // An accessory app is not frontmost by default, so activate before showing.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

/// The Capture tab of the Settings window.
struct CaptureSettingsSection: View {
    @ObservedObject var settings: CaptureSettings
    @ObservedObject var shortcuts: ShortcutCenter

    var body: some View {
        ShortcutRow(
            center: shortcuts, action: .captureRegion, titleKey: "settings.capture.shortcut",
            noteKey: "settings.capture.note", isOn: $settings.shortcutEnabled)
        ShortcutRow(center: shortcuts, action: .captureScrolling, titleKey: "settings.capture.scroll", noteKey: "settings.capture.scroll.note")
        ShortcutRow(center: shortcuts, action: .captureText, titleKey: "settings.capture.text", noteKey: "settings.capture.text.note")
        ShortcutRow(center: shortcuts, action: .pickColor, titleKey: "settings.capture.color", noteKey: "settings.capture.color.note")
    }
}
