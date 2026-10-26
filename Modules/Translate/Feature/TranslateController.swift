import AppKit
import ApplicationServices
import AVFoundation
import Combine
import NotchShell
import SwiftUI
import TranslateCore

/// Observable quick-translate settings; every change is written through to the store.
@MainActor
public final class TranslateSettings: ObservableObject {
    private let store: TranslateSettingsStore

    @Published public var isEnabled: Bool {
        didSet { store.isEnabled = isEnabled }
    }

    @Published public var target: String {
        didSet { store.target = target }
    }

    @Published public var smartSelection: Bool {
        didSet { store.smartSelection = smartSelection }
    }

    /// Empty for none.
    @Published public var alternate: String {
        didSet { store.alternate = alternate.isEmpty ? nil : alternate }
    }

    public init(store: TranslateSettingsStore) {
        self.store = store
        isEnabled = store.isEnabled
        smartSelection = store.smartSelection
        target = store.target
        alternate = store.alternate ?? ""
    }
}

/// State of the translation panel.
@MainActor
final class TranslateViewModel: ObservableObject {
    enum Phase: Equatable {
        case working
        case done(TranslatedText, target: String)
        case failed(String)
    }

    @Published var original = ""
    @Published var phase: Phase = .working

    /// True while the translation is being read aloud.
    @Published var isSpeaking = false
    /// The language the swap button would translate into; nil hides the button.
    @Published var swapTarget: String?

    var onCopy: (() -> Void)?
    var onReplace: (() -> Void)?
    var onClose: (() -> Void)?
    var onSpeak: (() -> Void)?
    /// Translate the same text into this language instead.
    var onRetarget: ((String) -> Void)?
}

/// Quick translate: ⌘⇧G translates the text selected in the app in front, through Google
/// Translate, and shows the result in a small panel. The selected text is sent to Google.
@MainActor
public final class TranslateController {
    private static let vKeyCode: CGKeyCode = 9
    private static let cKeyCode: CGKeyCode = 8

    private let settings: TranslateSettings
    private let shortcuts: ShortcutCenter
    private let smartSelection = SmartSelectionController()
    /// The on-device model, for other parts of the app and the settings.
    public let assistant = TextAssistant()
    private let viewModel = TranslateViewModel()
    private let session: URLSession
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var task: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    private var speakingWatch: Timer?

    public init(settings: TranslateSettings, shortcuts: ShortcutCenter) {
        self.settings = settings
        self.shortcuts = shortcuts
        // Nothing of a translation is kept: no cache, no cookies.
        session = URLSession(configuration: .ephemeral)
        viewModel.onCopy = { [weak self] in self?.copyResult() }
        viewModel.onReplace = { [weak self] in self?.replaceSelection() }
        viewModel.onClose = { [weak self] in self?.hidePanel() }
        viewModel.onSpeak = { [weak self] in self?.toggleSpeaking() }
        viewModel.onRetarget = { [weak self] target in
            guard let self else { return }
            self.present(self.viewModel.original, into: target)
        }
        smartSelection.onTranslate = { [weak self] text in self?.present(text) }
    }

    public func start() {
        shortcuts.setHandler(.translate) { [weak self] in self?.translateSelection() }
        settings.$isEnabled
            .sink { [weak self] isEnabled in self?.shortcuts.setEnabled(isEnabled, for: .translate) }
            .store(in: &cancellables)
        settings.$smartSelection
            .sink { [weak self] isEnabled in self?.smartSelection.setEnabled(isEnabled) }
            .store(in: &cancellables)
    }

    public func makeSettingsSection() -> AnyView {
        AnyView(TranslateSettingsSection(settings: settings, shortcuts: shortcuts))
    }

    /// Translates the given text and shows the panel, as the shortcut would for a selection.
    public func translate(_ text: String) {
        present(text)
    }

    /// Shows the Smart Selection bar for the given text at the pointer, as a fresh selection would.
    public func showSelectionBar(for text: String) {
        if let selection = SmartSelection(text) {
            smartSelection.show(selection)
        }
    }

    // MARK: - Selection

    /// Translates what is selected in the app in front, as the shortcut does.
    public func translateSelection() {
        if let text = SelectionReader.selection()?.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            present(text)
            return
        }
        // Some apps do not report their selection; copying it is the fallback. The selection
        // then also lands on the clipboard, like any copy.
        guard AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }
        let before = NSPasteboard.general.changeCount
        Self.postKey(Self.cKeyCode)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard NSPasteboard.general.changeCount != before,
                  let text = NSPasteboard.general.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                NSSound.beep()
                return
            }
            self?.present(text)
        }
    }

    private static func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Translating

    private var plan: TranslationPlan {
        TranslationPlan(target: settings.target, alternate: settings.alternate.isEmpty ? nil : settings.alternate)
    }

    /// - Parameter forcedTarget: the language the user asked for from the panel; nil lets
    ///   the plan choose, as the shortcut does.
    private func present(_ text: String, into forcedTarget: String? = nil) {
        task?.cancel()
        stopSpeaking()
        viewModel.original = text
        viewModel.phase = .working
        viewModel.swapTarget = nil
        // A translation asked for from the panel keeps the panel where it is.
        showPanel(atPointer: forcedTarget == nil || panel?.isVisible != true)

        let plan = self.plan
        task = Task { [weak self, session] in
            var target = forcedTarget ?? plan.firstTarget
            var result = await Self.fetch(text, target: target, session: session)
            // Text already in the main language goes to the other language instead.
            if forcedTarget == nil, let first = result, let retry = plan.retryTarget(detectedSource: first.sourceLanguage) {
                target = retry
                result = await Self.fetch(text, target: retry, session: session) ?? first
            }
            guard !Task.isCancelled, let self else { return }
            if let result {
                self.viewModel.phase = .done(result, target: target)
                self.viewModel.swapTarget = plan.swapTarget(from: target, source: result.sourceLanguage)
            } else {
                self.viewModel.phase = .failed(L10n.string(
                    text.count > GoogleTranslate.maxLength ? "translate.error.tooLong" : "translate.error.failed"))
            }
        }
    }

    private static func fetch(_ text: String, target: String, session: URLSession) async -> TranslatedText? {
        guard let request = GoogleTranslate.request(text: text, target: target),
              let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return GoogleTranslate.parse(data)
    }

    private var resultText: String? {
        if case .done(let translation, _) = viewModel.phase { return translation.text }
        return nil
    }

    /// Reads the translation aloud in its language; a second press stops it.
    private func toggleSpeaking() {
        if synthesizer.isSpeaking {
            stopSpeaking()
            return
        }
        guard case .done(let translation, let target) = viewModel.phase else { return }
        let utterance = AVSpeechUtterance(string: translation.text)
        utterance.voice = AVSpeechSynthesisVoice(language: TranslateLanguage.voiceCode(for: target))
        synthesizer.speak(utterance)
        viewModel.isSpeaking = true
        // The synthesizer reports its end to a delegate; asking it now and then is simpler
        // and the panel is short-lived.
        speakingWatch?.invalidate()
        speakingWatch = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.synthesizer.isSpeaking else { return }
                self.stopSpeaking()
            }
        }
    }

    private func stopSpeaking() {
        speakingWatch?.invalidate()
        speakingWatch = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        viewModel.isSpeaking = false
    }

    private func copyResult() {
        guard let resultText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        hidePanel()
    }

    /// Puts the translation where the selection is: onto the clipboard, then a paste into the
    /// app in front, which still holds the selection because the panel never took focus.
    private func replaceSelection() {
        guard let resultText, AXIsProcessTrusted() else {
            NSSound.beep()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(resultText, forType: .string)
        hidePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Self.postKey(Self.vKeyCode)
        }
    }

    // MARK: - Panel

    private func showPanel(atPointer: Bool = true) {
        let panel = self.panel ?? makePanel()
        if atPointer {
            let pointer = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
            let size = TranslatePanelView.size
            var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height - 14)
            if let visible = screen?.visibleFrame {
                origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
                origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
            }
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
        }
        panel.orderFrontRegardless()

        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                self?.hidePanel()
            }
        }
    }

    private func hidePanel() {
        stopSpeaking()
        task?.cancel()
        panel?.orderOut(nil)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func makePanel() -> NSPanel {
        // Non-activating and never key: the app in front keeps its selection and its focus.
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: TranslatePanelView(model: viewModel))
        self.panel = panel
        return panel
    }
}

/// The small panel that shows a translation.
struct TranslatePanelView: View {
    static let size = CGSize(width: 380, height: 220)

    @ObservedObject var model: TranslateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                AraIcon.translate.image
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AraPalette.label)
                AraLabel(header)
                Spacer()
                AraIconButton(.close, look: .bare, size: .small) { model.onClose?() }
            }

            Text(model.original)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.5))
                .lineLimit(2)

            Rectangle().fill(AraPalette.hairline).frame(height: 1)

            Group {
                switch model.phase {
                case .working:
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .done(let translation, _):
                    ScrollView {
                        Text(translation.text)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .failed(let message):
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.6))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)

            if case .done = model.phase {
                HStack(spacing: 6) {
                    AraIconButton(.copy, look: .accent, help: L10n.string("translate.copy")) { model.onCopy?() }
                    AraIconButton(.replace, help: L10n.string("translate.replace")) { model.onReplace?() }
                    AraIconButton(
                        model.isSpeaking ? .stop : .speak, isOn: model.isSpeaking,
                        help: L10n.string(model.isSpeaking ? "translate.speak.stop" : "translate.speak")
                    ) { model.onSpeak?() }
                    if let other = model.swapTarget {
                        AraIconButton(
                            .swapLanguage,
                            help: String(format: L10n.string("translate.swap"), TranslateLanguage.name(for: other))
                        ) { model.onRetarget?(other) }
                    }
                    Spacer()
                    Text("Google Translate")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.35))
                }
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .araCard(radius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .araHue(.sky)
    }

    private var header: String {
        if case .done(let translation, let target) = model.phase {
            let source = translation.sourceLanguage.map(TranslateLanguage.name(for:)) ?? "?"
            return "\(source) → \(TranslateLanguage.name(for: target))"
        }
        return L10n.string("translate.title")
    }
}

/// Translation and the selection bar, in Settings › Tools and shortcuts.
struct TranslateSettingsSection: View {
    @ObservedObject var settings: TranslateSettings
    @ObservedObject var shortcuts: ShortcutCenter

    var body: some View {
        ShortcutRow(
            center: shortcuts, action: .translate, titleKey: "settings.translate.enabled",
            noteKey: "settings.translate.note", isOn: $settings.isEnabled)
        Group {
            Picker(L10n.string("settings.translate.target"), selection: $settings.target) {
                ForEach(TranslateLanguage.all) { language in
                    Text(language.name).tag(language.code)
                }
            }
            // Said in full with the language chosen above: "If it is already Vietnamese, translate into".
            Picker(String(
                format: L10n.string("settings.translate.alternate"),
                TranslateLanguage.all.first { $0.code == settings.target }?.name ?? settings.target
            ), selection: $settings.alternate) {
                Text(L10n.string("settings.translate.alternate.none")).tag("")
                ForEach(TranslateLanguage.all) { language in
                    Text(language.name).tag(language.code)
                }
            }
        }
        .disabled(!settings.isEnabled)
        Toggle(isOn: $settings.smartSelection) {
            Text(L10n.string("settings.selection.enabled"))
            AraSettingsNote(L10n.string("settings.selection.note"))
        }
    }
}
