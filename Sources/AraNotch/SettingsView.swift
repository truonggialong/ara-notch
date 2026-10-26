import NotchCore
import NotchShell
import SwiftUI

/// One tab of the Settings window.
struct SettingsTab: Identifiable {
    let id: String
    let titleKey: String
    let symbolName: String
    /// The beginnings of the string keys of what is in the tab; their texts are what a search
    /// looks through.
    var searchPrefixes: [String] = []
    let content: AnyView
}

/// Which Settings tab is showing, and what is typed in the search field. An object rather
/// than `@State`, so the app can open the window on a particular tab.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selectedTabID: String
    @Published var query = ""

    init(selectedTabID: String) {
        self.selectedTabID = selectedTabID
    }
}

struct SettingsView: View {
    static let size = CGSize(width: 680, height: 640)
    private static let sidebarWidth: CGFloat = 200

    @ObservedObject var navigation: SettingsNavigation
    let tabs: [SettingsTab]
    /// The names of everything in each tab, read once from the strings in use.
    let index: [SettingsSearch.Section]

    init(navigation: SettingsNavigation, tabs: [SettingsTab]) {
        self.navigation = navigation
        self.tabs = tabs
        index = Self.makeIndex(for: tabs)
    }

    /// A list of sections on the left rather than tabs across the top: there are more
    /// sections than fit across a window. Typing in the field above it finds a setting by name.
    /// Both are cards lying on the theme's ground.
    var body: some View {
        let results = SettingsSearch.results(for: navigation.query, in: index)
        let shown = tabs.first { $0.id == navigation.selectedTabID } ?? tabs.first
        return HStack(spacing: 12) {
            VStack(spacing: 8) {
                searchField
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(results, id: \.id) { result in
                            if let tab = tabs.first(where: { $0.id == result.id }) {
                                sidebarRow(tab, matches: result.phrases)
                            }
                        }
                        if results.isEmpty {
                            Text(L10n.string("settings.search.none"))
                                .padding(.top, 16)
                                .font(.caption)
                                .foregroundStyle(AraTheme.secondaryText)
                        }
                    }
                }
            }
            .padding(8)
            .frame(width: Self.sidebarWidth)
            .araCard()
            if let tab = shown {
                Form {
                    tab.content
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                // Switches and sliders in the outline's red, not the system's accent.
                .tint(AraPalette.brand)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .araCard()
                .clipShape(RoundedRectangle(cornerRadius: AraTheme.cardRadius, style: .continuous))
                // A different section is a different form, not the old one with new rows.
                .id(tab.id)
            }
        }
        .padding(12)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(AraPalette.ground)
        .onChange(of: navigation.query) { _, _ in
            // The first match is shown at once, so typing a name is enough to get there.
            let matches = SettingsSearch.results(for: navigation.query, in: index)
            if let first = matches.first, !matches.contains(where: { $0.id == navigation.selectedTabID }) {
                navigation.selectedTabID = first.id
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            AraIcon.search.image
                .foregroundStyle(AraPalette.label)
            TextField(L10n.string("settings.search.placeholder"), text: $navigation.query)
                .textFieldStyle(.plain)
            if !navigation.query.isEmpty {
                Button {
                    navigation.query = ""
                } label: {
                    AraIcon.clear.image
                        .foregroundStyle(AraTheme.tertiaryText)
                }
                .buttonStyle(AraPressStyle())
                .accessibilityLabel(AraIcon.clear.label)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .frame(height: 28)
        .araField()
    }

    private func sidebarRow(_ tab: SettingsTab, matches: [String]) -> some View {
        let isSelected = tab.id == navigation.selectedTabID
        return Button {
            navigation.selectedTabID = tab.id
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Label {
                    Text(L10n.string(tab.titleKey))
                        .lineLimit(1)
                } icon: {
                    // A section about a page of the notch is listed in that page's colour.
                    Image(systemName: tab.symbolName)
                        .foregroundStyle(AraPalette.label(in: Self.hue(ofTab: tab.id)))
                        .frame(width: 20)
                }
                .font(.system(size: 12, weight: .medium))
                // What in this section matched the search.
                ForEach(matches.prefix(2), id: \.self) { match in
                    Text(match)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .opacity(0.65)
                        .padding(.leading, 28)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .araRow(isSelected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(AraPressStyle(depth: 0.97))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func hue(ofTab id: String) -> AraHue? {
        switch id {
        case "clipboard": .peach
        case "agents": .lilac
        default: nil
        }
    }

    /// The texts of every string whose key belongs to a tab, in the language in use.
    private static func makeIndex(for tabs: [SettingsTab]) -> [SettingsSearch.Section] {
        let strings = Bundle.main.url(forResource: "Localizable", withExtension: "strings")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] } ?? [:]
        return tabs.map { tab in
            let phrases = strings
                .filter { key, _ in tab.searchPrefixes.contains { key.hasPrefix($0) } }
                // Explanations are long; a search is for names.
                .filter { key, value in !key.hasSuffix(".note") && value.count <= 70 && !value.contains("%") }
                .sorted { $0.key < $1.key }
                .map(\.value)
            return SettingsSearch.Section(id: tab.id, title: L10n.string(tab.titleKey), phrases: phrases)
        }
    }
}

/// The permissions the app can use, at the top of Settings › General: one line when all are
/// given, otherwise a line for each that is missing with a button to the pane that gives it.
@MainActor
final class PermissionsState: ObservableObject {
    @Published var missing: [WelcomePermission] = []
    private var timer: Timer?

    init() {
        refresh()
        // Permissions are given in System Settings, so they are read again while Settings is open.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        let missing = WelcomeWindowController.permissions.filter { !$0.isGranted() }
        if missing.map(\.id) != self.missing.map(\.id) {
            self.missing = missing
        }
    }
}

struct PermissionsCard: View {
    @StateObject private var state = PermissionsState()

    var body: some View {
        if state.missing.isEmpty {
            Label(L10n.string("settings.permissions.all"), systemImage: AraIcon.completed.symbolName)
                .foregroundStyle(AraPalette.value)
        } else {
            ForEach(state.missing) { permission in
                LabeledContent {
                    Button(L10n.string("welcome.permission.open")) {
                        if let url = URL(string: permission.settingsURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                } label: {
                    Text(L10n.string(permission.titleKey))
                    AraSettingsNote(L10n.string(permission.reasonKey))
                }
            }
        }
    }
}

/// How the notch opens: by the pointer, by a swipe, by both, or only by a click or a shortcut.
enum OpenGesture: String, CaseIterable {
    case hoverAndSwipe, hover, swipe, click

    init(hover: Bool, swipe: Bool) {
        switch (hover, swipe) {
        case (true, true): self = .hoverAndSwipe
        case (true, false): self = .hover
        case (false, true): self = .swipe
        case (false, false): self = .click
        }
    }

    var opensOnHover: Bool { self == .hoverAndSwipe || self == .hover }
    var opensOnSwipe: Bool { self == .hoverAndSwipe || self == .swipe }
}

/// Settings › General: the permissions, how the notch opens, shows and looks, starting and
/// updating.
struct GeneralSettingsSection: View {
    @ObservedObject var settings: ShellSettings
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var updater: AppUpdater

    /// "0.12.0 (24)": the version in use.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "–") (\(info?["CFBundleVersion"] as? String ?? "–"))"
    }

    var body: some View {
        Section(L10n.string("settings.permissions")) {
            PermissionsCard()
        }
        Section(L10n.string("settings.section.notch")) {
            Picker(selection: Binding(
                get: { OpenGesture(hover: settings.openOnHover, swipe: settings.swipeToOpen) },
                set: { gesture in
                    settings.openOnHover = gesture.opensOnHover
                    settings.swipeToOpen = gesture.opensOnSwipe
                }
            )) {
                ForEach(OpenGesture.allCases, id: \.self) { gesture in
                    Text(L10n.string("settings.openGesture.\(gesture.rawValue)")).tag(gesture)
                }
            } label: {
                Text(L10n.string("settings.openGesture"))
                AraSettingsNote(L10n.string("settings.openGesture.note"))
            }
            LabeledContent {
                HStack {
                    Slider(value: $settings.hoverDelay, in: ShellSettingsStore.hoverDelayRange, step: 0.05)
                    Text(hoverDelayText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            } label: {
                Text(L10n.string("settings.hoverDelay"))
                AraSettingsNote(L10n.string("settings.hoverDelay.note"))
            }
            .disabled(!settings.openOnHover)
            Picker(L10n.string("settings.notchSize"), selection: $settings.notchSize) {
                ForEach(NotchSize.allCases, id: \.self) { size in
                    Text(L10n.string("settings.notchSize.\(size.rawValue)")).tag(size)
                }
            }
            Picker(L10n.string("settings.displayMode"), selection: $settings.displayMode) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Text(L10n.string("settings.displayMode.\(mode.rawValue)")).tag(mode)
                }
            }
            // A choice between two looks rather than a switch whose off says nothing.
            Picker(selection: $settings.pillStyle) {
                Text(L10n.string("settings.pillStyle.bar")).tag(false)
                Text(L10n.string("settings.pillStyle.pill")).tag(true)
            } label: {
                Text(L10n.string("settings.pillStyle"))
                AraSettingsNote(L10n.string("settings.pillStyle.note"))
            }
            Toggle(isOn: $settings.hidesInFullScreen) {
                Text(L10n.string("settings.hidesInFullScreen"))
                AraSettingsNote(L10n.string("settings.hidesInFullScreen.note"))
            }
            Picker(selection: $settings.appearance) {
                ForEach(AppAppearance.allCases, id: \.self) { appearance in
                    Text(L10n.string("settings.appearance.\(appearance.rawValue)")).tag(appearance)
                }
            } label: {
                Text(L10n.string("settings.appearance"))
                AraSettingsNote(L10n.string("settings.appearance.note"))
            }
        }
        Section(L10n.string("settings.section.app")) {
            // Kept as macOS keeps a language chosen for an app; it takes effect when the app opens.
            Picker(selection: Binding(
                get: { AppLanguage.read(fromAppDomain: Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))) },
                set: { language in
                    language.write(to: .standard)
                    AppRelauncher.relaunch()
                }
            )) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(L10n.string("settings.language.\(language.rawValue)")).tag(language)
                }
            } label: {
                Text(L10n.string("settings.language"))
                AraSettingsNote(L10n.string("settings.language.note"))
            }
            Toggle(isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) })) {
                Text(L10n.string("settings.launchAtLogin"))
                if let problem = loginItem.problem {
                    Text(problem).font(.caption).foregroundStyle(AraPalette.warning)
                }
            }
            LabeledContent {
                HStack {
                    Button(L10n.string("settings.updates.check")) { updater.checkForUpdates() }
                    Toggle("", isOn: $updater.checksAutomatically)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            } label: {
                Text(L10n.string("settings.updates.automatic"))
                AraSettingsNote(String(format: L10n.string("settings.updates.version"), Self.version))
            }
            .disabled(!updater.isAvailable)
        }
    }

    private var hoverDelayText: String {
        Duration.milliseconds(Int((settings.hoverDelay * 1000).rounded()))
            .formatted(.units(allowed: [.seconds], width: .abbreviated, fractionalPart: .show(length: 2)))
    }
}

/// Settings › Notch pages: which pages there are and in what order, the overview's tiles, and
/// the page that shows first. The pages' own choices follow, from their features.
struct PagesSettingsSection: View {
    @ObservedObject var settings: ShellSettings
    /// The notch, for the list of pages. Weak: the Settings window must not keep it alive.
    weak var notch: NotchController?
    /// The overview's own line: putting its tiles back.
    let overviewRow: AnyView
    @StateObject private var drag = PageDragState()

    var body: some View {
        let pages = notch?.allPages ?? []
        Section {
            ForEach(pages) { page in
                HStack {
                    // Rows are dragged to change the order.
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                    Image(systemName: page.symbolName)
                        .frame(width: 20)
                    Text(L10n.string(page.titleKey))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { !(notch?.isPageHidden(id: page.id) ?? false) },
                        set: { notch?.setPageHidden(!$0, id: page.id) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .contentShape(Rectangle())
                .opacity(drag.draggedID == page.id ? 0.4 : 1)
                // A form's own reordering does not work on the Mac; each row takes drops itself.
                .onDrag {
                    drag.begin(page.id)
                    return NSItemProvider(object: page.id as NSString)
                }
                .onDrop(of: [.text], delegate: PageDropDelegate(targetID: page.id, notch: notch, drag: drag))
            }
        } header: {
            Text(L10n.string("settings.pages"))
        } footer: {
            AraSettingsNote(L10n.string("settings.pages.note"))
        }
        Section {
            overviewRow
            Picker(L10n.string("settings.pages.start"), selection: $settings.startPage) {
                Text(L10n.string("settings.pages.start.last")).tag(String?.none)
                ForEach(pages) { page in
                    Text(L10n.string(page.titleKey)).tag(String?.some(page.id))
                }
            }
        }
    }
}

/// The page row being dragged in Settings › Notch pages.
@MainActor
final class PageDragState: ObservableObject {
    @Published var draggedID: String?
    private var watch: Timer?

    /// A drag let go outside the list reports nothing: the row is put back once the button is up.
    func begin(_ id: String) {
        draggedID = id
        watch?.invalidate()
        watch = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, NSEvent.pressedMouseButtons == 0 else { return }
                self.watch?.invalidate()
                self.watch = nil
                self.draggedID = nil
            }
        }
    }
}

/// Moves the dragged page to the row it passes over, so the list shows the new order as the
/// pointer moves; dropping only ends the drag.
@MainActor
struct PageDropDelegate: DropDelegate {
    let targetID: String
    weak var notch: NotchController?
    let drag: PageDragState

    func dropEntered(info: DropInfo) {
        guard let dragged = drag.draggedID, dragged != targetID, let notch else { return }
        let order = notch.allPages.map(\.id)
        guard let from = order.firstIndex(of: dragged), let to = order.firstIndex(of: targetID) else { return }
        notch.movePage(id: dragged, by: to - from)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        drag.draggedID = nil
        return true
    }
}

/// The notch's own lines in Settings › Advanced: fine points that most people leave as they are.
struct ShellAdvancedSettings: View {
    @ObservedObject var settings: ShellSettings

    var body: some View {
        Toggle(isOn: $settings.hapticsEnabled) {
            Text(L10n.string("settings.haptics"))
            AraSettingsNote(L10n.string("settings.haptics.note"))
        }
        Toggle(isOn: $settings.hidesFromCapture) {
            Text(L10n.string("settings.hidesFromCapture"))
            AraSettingsNote(L10n.string("settings.hidesFromCapture.note"))
        }
    }
}

/// Removing the app, at the foot of Settings › Advanced.
struct UninstallSettings: View {
    let onUninstall: () -> Void

    var body: some View {
        LabeledContent {
            Button(L10n.string("settings.uninstall.button"), role: .destructive, action: onUninstall)
        } label: {
            Text(L10n.string("settings.uninstall.label"))
                .foregroundStyle(AraPalette.danger)
            AraSettingsNote(L10n.string("settings.uninstall.note"))
        }
    }
}

/// The notch's own shortcuts in Settings › Tools and shortcuts.
struct ShellToolSettings: View {
    @ObservedObject var shortcuts: ShortcutCenter

    var body: some View {
        ShortcutRow(center: shortcuts, action: .openNotch, titleKey: "shortcut.openNotch")
        ShortcutRow(center: shortcuts, action: .hideNotch, titleKey: "shortcut.hideNotch", noteKey: "settings.tools.hideNotch.note")
    }
}
