import AgentCore
import AgentFeature
import AppKit
import CalendarCore
import CalendarFeature
import CaptureCore
import CaptureFeature
import Combine
import ClipboardCore
import ClipboardFeature
import FilesFeature
import MediaCore
import MediaFeature
import NotchCore
import NotchShell
import NotesCore
import NotesFeature
import OverviewCore
import OverviewFeature
import SwiftUI
import SystemEventsCore
import SystemEventsFeature
import TimerCore
import TimerFeature
import ToolsFeature
import TranslateCore
import TranslateFeature
import WindowsCore
import WindowsFeature

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var clipboard: ClipboardController?
    private var systemEvents: SystemEventsController?
    private var timer: TimerController?
    private var media: MediaController?
    private var files: FilesController?
    private var agents: AgentController?
    private var windows: WindowsController?
    private var translate: TranslateController?
    private var calendar: CalendarController?
    private var notes: NotesController?
    private var capture: CaptureController?
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var welcome: WelcomeWindowController?
    private var overview: OverviewController?
    private var updater: AppUpdater?
    private var appearanceWatch: AnyCancellable?

    func applicationWillTerminate(_ notification: Notification) {
        // Deletions still waiting to be undone are carried out: there will be no later.
        clipboard?.flushPendingDeletions(all: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = LaunchArguments(CommandLine.arguments)
        RetiredSettings.remove(from: .standard)
        NSApp.setActivationPolicy(arguments.showInDock ? .regular : .accessory)
        MainMenu.install()
        // A copy started for an automated check, with data of its own, does not look for updates.
        let updater = AppUpdater(isTestRun: arguments.dataDirectory != nil, feedOverride: arguments.updateFeed)
        self.updater = updater

        // An order kept from before the overview page existed gets it in front.
        let controller = NotchController(
            settings: ShellSettings(store: ShellSettingsStore(defaults: .standard)), leadingPageID: OverviewLayout.pageID)
        let shellSettings = controller.settings
        // One look for every window of the app; the notch keeps its own dark one.
        appearanceWatch = shellSettings.$appearance.sink { appearance in
            NSApp.appearance = switch appearance {
            case .system: nil
            case .dark: NSAppearance(named: .darkAqua)
            case .light: NSAppearance(named: .aqua)
            }
        }
        controller.treatsDisplaysAsNotchless = arguments.noHardwareNotch
        let clipboard = ClipboardController(
            directory: arguments.dataDirectory ?? Self.defaultDataDirectory,
            settings: ClipboardSettings(store: ClipboardSettingsStore(defaults: .standard)),
            notch: controller,
            pasteboard: arguments.pasteboardName.map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general)
        let systemEvents = SystemEventsController(
            settings: AlertSettings(store: AlertSettingsStore(defaults: .standard)), notch: controller)
        let timer = TimerController(
            settings: TimerSettings(store: TimerSettingsStore(defaults: .standard)), notch: controller)
        let media = MediaController(
            settings: MediaSettings(store: MediaSettingsStore(defaults: .standard)), notch: controller)
        let files = FilesController()
        let agents = AgentController(
            settings: AgentSettings(store: AgentSettingsStore(defaults: .standard)), notch: controller,
            eventsFile: arguments.agentEventsFile, claudeSettingsFile: arguments.claudeSettingsFile,
            usageFile: arguments.claudeUsageFile, codexSessionsDirectory: arguments.codexSessionsDirectory)
        let windows = WindowsController(settings: WindowSettings(store: WindowSettingsStore(defaults: .standard)))
        let translate = TranslateController(
            settings: TranslateSettings(store: TranslateSettingsStore(defaults: .standard)), shortcuts: controller.shortcuts)
        let calendar = CalendarController(
            settings: CalendarSettings(store: CalendarSettingsStore(defaults: .standard)), notch: controller)
        let notes = NotesController(
            settings: NotesSettings(store: NotesSettingsStore(defaults: .standard)), notch: controller)
        if arguments.simulateAgenda {
            calendar.simulate()
        }
        if let picker = arguments.calendarPicker {
            calendar.showPicker(named: picker)
        }
        if arguments.checkUpdates {
            // After launch has settled, so the update window is not behind the app's own.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak updater] in updater?.checkForUpdatesWhenReady() }
        }
        let capture = CaptureController(
            settings: CaptureSettings(store: CaptureSettingsStore(defaults: .standard)), shortcuts: controller.shortcuts)
        // Pages are registered before the Settings window is built: its General tab lists them.
        // The overview comes first among the tabs, so it is registered first; its tiles are
        // handed over once everything they show has been made.
        let overview = OverviewController(
            settings: OverviewSettings(store: OverviewSettingsStore(defaults: .standard)),
            trialArrangement: arguments.overviewArrangement.map(OverviewGrid.arrangement(from:)))
        self.overview = overview
        controller.register(page: overview.makePage(notch: controller))
        controller.register(page: clipboard.makePage())
        controller.register(page: media.makePage())
        controller.register(page: timer.makePage())
        controller.register(page: calendar.makePage())
        controller.register(page: notes.makePage())
        controller.register(page: files.makePage())
        controller.register(page: agents.makePage())
        // The tools page: what otherwise takes a shortcut or the menu bar. The notch closes
        // first, so it is out of the way of a capture and the app in front is seen again.
        let tool: (String, @escaping @MainActor () -> Void) -> NotchTool = { id, action in
            NotchTool(id: id) { [weak controller] in
                controller?.close()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { action() }
            }
        }
        let tools = [
            tool("capture") { [weak capture] in capture?.capture() },
            tool("scroll") { [weak capture] in capture?.captureScrolling() },
            tool("text") { [weak capture] in capture?.captureText() },
            tool("color") { [weak capture] in capture?.pickColor() },
            tool("translate") { [weak translate] in translate?.translateSelection() },
            tool("panel") { [weak clipboard] in clipboard?.showPanel() },
            tool("library") { [weak clipboard] in clipboard?.showLibrary() },
            tool("note") { [weak notes] in notes?.newNote() },
        ]
        // The overview's quick tools are the four used most: capture, read text, pick a colour, translate.
        let toolsPage = ToolsController(tools: tools, quickToolIDs: ["capture", "text", "color", "translate"])
        controller.register(page: toolsPage.makePage())
        overview.setTiles([
            .media: media.makeOverviewTile(), .calendar: calendar.makeOverviewTile(), .timer: timer.makeOverviewTile(),
            .clipboard: clipboard.makeOverviewTile(), .agents: agents.makeOverviewTile(),
            .tools: toolsPage.makeOverviewTile(),
            .device: systemEvents.makeOverviewTile(volume: media.makeVolumeRow()),
        ])
        controller.onFileDrag = { [weak controller, weak files] in
            controller?.selectPage(id: "files")
            files?.filesAreBeingDragged()
        }
        let welcome = WelcomeWindowController(settings: shellSettings) { [weak controller] in
            controller?.shortcuts.label(for: .clipboardPanel) ?? ""
        }
        self.welcome = welcome
        controller.register(page: NotchPage(id: "about", titleKey: "page.about.title", symbolName: "info.circle") { [weak controller, weak welcome] in
            AboutPage(
                geometry: controller?.geometry, updater: updater,
                onShowGuide: {
                    controller?.close()
                    welcome?.show()
                },
                onCheckForUpdates: { controller?.close() })
        })
        // A newer version found while the app is out of the way says so beside the notch.
        updater.onFound = { [weak controller] version in
            controller?.present(AppUpdater.reminder(forVersion: version))
        }
        // Seven sections, each about one thing. A line sits where a person would look for it:
        // how the notch opens and shows in General, what a page shows with the pages, what the
        // clipboard keeps with the clipboard, only what speaks beside the notch in Notices.
        let settingsWindow = SettingsWindowController(tabs: [
            SettingsTab(
                id: "general", titleKey: "settings.section.general", symbolName: "gearshape",
                searchPrefixes: ["settings.permissions", "welcome.permission.", "settings.openGesture", "settings.hoverDelay", "settings.notchSize", "settings.displayMode", "settings.pillStyle", "settings.hidesInFullScreen", "settings.appearance", "settings.language", "settings.launchAtLogin", "settings.updates", "update."],
                content: AnyView(GeneralSettingsSection(settings: shellSettings, loginItem: LoginItem(), updater: updater))),
            SettingsTab(
                id: "pages", titleKey: "settings.section.pages", symbolName: "square.grid.2x2",
                searchPrefixes: ["settings.pages", "settings.overview", "settings.media.enabled", "settings.media.lyrics", "settings.calendar.lunar", "settings.notes.defaultFolder", "settings.notes.automation", "settings.notes.fullDisk", "settings.notes.permission"],
                content: AnyView(Group {
                    PagesSettingsSection(settings: shellSettings, notch: controller, overviewRow: overview.makeSettingsRow())
                    Section(L10n.string("settings.pages.options")) {
                        media.makePageSettings()
                        calendar.makePageSettings()
                        notes.makePageSettings()
                    }
                })),
            SettingsTab(
                id: "clipboard", titleKey: "settings.section.clipboard", symbolName: "doc.on.clipboard",
                searchPrefixes: ["settings.clipboard.recording", "settings.clipboard.pause", "settings.clipboard.resume", "settings.clipboard.retention", "settings.clipboard.maxItems", "settings.clipboard.copyFeedback", "settings.clipboard.copySign", "settings.clipboard.pasteOnClick", "settings.clipboard.skipsSensitive", "settings.clipboard.vaultTouchID", "settings.clipboard.quickPasteBoard", "settings.clipboard.ignoredApps", "settings.shortcuts.numberRow", "settings.shortcuts.quickPaste", "settings.shortcuts.recentPaste", "settings.clipboard.data", "settings.clipboard.linkPreviews", "settings.clipboard.readsTextInImages", "settings.clipboard.timeMachine", "settings.clipboard.backup", "settings.clipboard.clear"],
                content: AnyView(Group {
                    clipboard.makeSettingsSection()
                    Section(L10n.string("settings.clipboard.data")) {
                        clipboard.makeDataSettings()
                    }
                })),
            SettingsTab(
                id: "alerts", titleKey: "settings.section.alerts", symbolName: "bell",
                searchPrefixes: ["settings.alerts", "settings.agents.announce", "settings.media.announce", "settings.media.whilePlaying", "settings.calendar.alerts", "settings.timer"],
                content: AnyView(Group {
                    Section {
                        systemEvents.makeSettingsSection()
                        agents.makeNoticeSettings()
                        media.makeNoticeSettings()
                        calendar.makeSettingsSection()
                        timer.makeSettingsSection()
                    } header: {
                        Text(L10n.string("settings.alerts.screen"))
                    }
                })),
            SettingsTab(
                id: "tools", titleKey: "settings.section.tools", symbolName: "keyboard",
                searchPrefixes: ["settings.capture", "settings.translate", "settings.selection", "settings.windows", "settings.clipboard.hotKey", "settings.notes.newNote", "shortcut.", "settings.shortcuts.restore"],
                content: AnyView(Group {
                    Section {
                        clipboard.makeToolSettings()
                        notes.makeToolSettings()
                        ShellToolSettings(shortcuts: controller.shortcuts)
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("settings.tools.notch"))
                            AraSettingsNote(L10n.string("settings.shortcuts.note"))
                        }
                    }
                    Section(L10n.string("settings.section.capture")) {
                        capture.makeSettingsSection()
                    }
                    Section(L10n.string("settings.section.translate")) {
                        translate.makeSettingsSection()
                    }
                    Section(L10n.string("settings.section.windows")) {
                        windows.makeSettingsSection()
                    }
                })),
            SettingsTab(
                id: "agents", titleKey: "settings.section.agents", symbolName: "terminal",
                searchPrefixes: ["settings.agents.claude", "settings.agents.account", "settings.agents.hooks", "settings.agents.statusLine", "settings.agents.codex", "settings.clipboard.mcp"],
                content: AnyView(Group {
                    agents.makeSettingsSection()
                    Section(L10n.string("settings.clipboard.mcp")) {
                        clipboard.makeAgentAccessSettings()
                    }
                })),
            SettingsTab(
                id: "advanced", titleKey: "settings.section.advanced", symbolName: "slider.horizontal.3",
                searchPrefixes: ["settings.haptics", "settings.hidesFromCapture", "settings.uninstall"],
                content: AnyView(Group {
                    Section {
                        ShellAdvancedSettings(settings: shellSettings)
                        UninstallSettings { [weak agents] in
                            guard let agents else { return }
                            Uninstaller(agents: agents, testHome: arguments.uninstallHome).confirmAndRun()
                        }
                    }
                })),
        ])

        controller.onOpenSettings = { [weak controller, weak settingsWindow] in
            controller?.close()
            settingsWindow?.show()
        }
        MainMenu.setOpenSettings { [weak controller, weak settingsWindow] in
            controller?.close()
            settingsWindow?.show()
        }
        statusItem = StatusItemController(
            onOpenLibrary: { [weak clipboard] in clipboard?.showLibrary() },
            onNewNote: { [weak notes] in notes?.newNote() },
            onPause: { [weak clipboard] pause in
                if let pause {
                    clipboard?.pause(pause)
                } else {
                    clipboard?.resume()
                }
            },
            recordingState: { [weak clipboard] in clipboard?.recordingState ?? .recording },
            onCapture: { [weak capture] in capture?.capture() },
            onScrollCapture: { [weak capture] in capture?.captureScrolling() },
            onCaptureText: { [weak capture] in capture?.captureText() },
            onPickColor: { [weak capture] in capture?.pickColor() },
            onOpenSettings: { [weak settingsWindow] in settingsWindow?.show() },
            onCheckForUpdates: { [weak updater] in updater?.checkForUpdates() })

        clipboard.allowsLocalLinkPreviews = arguments.allowLocalLinkPreviews
        controller.start()
        clipboard.start()
        systemEvents.start()
        if let line = arguments.simulatedNowPlaying {
            media.simulate(line: line)
        }
        if !arguments.simulatedSoundingApps.isEmpty {
            media.simulate(soundingBundleIDs: arguments.simulatedSoundingApps)
        }
        media.start()
        if arguments.installClaudeHooks {
            agents.installHooks()
        }
        if arguments.removeClaudeHooks {
            agents.removeHooks()
        }
        if arguments.installClaudeStatusLine {
            agents.installStatusLine()
        }
        if arguments.removeClaudeStatusLine {
            agents.removeStatusLine()
        }
        agents.start()
        if let file = arguments.agentSummaryFile {
            // After the first check of the watched files.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                try? agents.summary.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        windows.start()
        translate.start()
        calendar.start()
        notes.start()
        capture.start()
        capture.onNotice = { [weak controller] symbol, message in
            controller?.present(NotchLiveActivity(
                id: "capture.notice", priority: 2, duration: 2.5,
                sign: AraSign(icon: .symbol(symbol), mark: L10n.string("sign.capture"), rows: [AraSign.Row(message)])))
        }
        clipboard.cutOutSubject = { [weak capture] data, completion in
            if let capture {
                capture.cutOutSubject(fromImageData: data, completion: completion)
            } else {
                completion(nil)
            }
        }
        clipboard.createReminder = { [weak calendar] title, notes, due, completion in
            if let calendar {
                calendar.createReminder(title: title, notes: notes, due: due, completion: completion)
            } else {
                completion(false)
            }
        }
        clipboard.assistantActions = translate.assistant.availableActions.map(\.rawValue)
        clipboard.assistant = { [weak translate] action, text, completion in
            guard let translate, let action = TextAssistant.Action(rawValue: action) else {
                completion(nil)
                return
            }
            translate.assistant.run(action, on: text, completion: completion)
        }
        clipboard.recognizeText = { [weak capture] data, completion in
            if let capture {
                capture.recognizeText(inImageData: data, completion: completion)
            } else {
                completion("")
            }
        }
        if arguments.newNote {
            notes.newNote()
        }
        if arguments.showNotes {
            notes.showWindow()
        }
        if let dump = arguments.dumpNoteData {
            print(notes.dumpNoteData(noteID: dump.id, to: dump.file) ? "note data written to \(dump.file.path)" : "note data not written")
        }
        if let file = arguments.checkRemindersFile {
            try? "can write reminders: \(calendar.canWriteReminders())\n".write(to: file, atomically: true, encoding: .utf8)
        }
        if let file = arguments.cutOutFile, let output = arguments.captureOutput, let data = try? Data(contentsOf: file) {
            capture.cutOutSubject(fromImageData: data) { result in
                try? (result ?? Data()).write(to: output)
            }
        }
        if arguments.pickColor {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { capture.pickColor() }
        }
        if let rect = arguments.captureRect {
            if arguments.captureScrolls {
                // After a moment, so the page the check put under the rectangle is ready.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    capture.captureScrolling(in: rect, framesDirectory: arguments.captureOutput)
                }
            } else {
                capture.capture(rect: rect)
            }
        }
        if let file = arguments.annotateFile {
            print("capture editor opened: \(capture.openEditor(forImageAt: file))")
        }
        if let file = arguments.ocrFile, let output = arguments.captureOutput {
            capture.recognizeText(inImageAt: file, writingTo: output)
        }
        if let file = arguments.renderSampleFile, let output = arguments.captureOutput {
            capture.renderSample(ontoImageAt: file, writingTo: output)
        }
        if let file = arguments.agendaSummaryFile {
            calendar.writeSummary(to: file)
        }
        if let text = arguments.translateText {
            translate.translate(text)
        }
        if let text = arguments.selectionBarText {
            translate.showSelectionBar(for: text)
        }
        if let zone = arguments.snapZone {
            // After a moment, so the app the test put in front has its window ready.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                print("snap \(zone): \(windows.snap(zoneNamed: zone))")
            }
        }
        if let file = arguments.audioOutputsFile {
            try? media.outputSummary.write(to: file, atomically: true, encoding: .utf8)
        }

        self.controller = controller
        self.clipboard = clipboard
        self.systemEvents = systemEvents
        self.timer = timer
        self.media = media
        self.files = files
        self.agents = agents
        self.windows = windows
        self.translate = translate
        self.calendar = calendar
        self.notes = notes
        self.capture = capture
        self.settingsWindow = settingsWindow

        // Launch arguments for automated checks.
        if arguments.seedClipboard {
            SampleClips.add(to: clipboard)
        }
        for seconds in arguments.timerSeconds {
            timer.start(seconds: seconds)
        }
        if arguments.seedBoards {
            SampleClips.addBoards(to: clipboard)
        }
        if let passcode = arguments.seedVaultPasscode {
            clipboard.seedVault(passcode: passcode, lockingBoardNamed: "Công việc")
        }
        if let passcode = arguments.unlockVaultPasscode {
            clipboard.unlockVault(passcode: passcode)
        }
        if let board = arguments.selectedBoard {
            clipboard.selectBoard(named: board)
        }
        if arguments.editNewBoard {
            clipboard.beginNewBoard()
        }
        if let url = arguments.restoreBackup {
            do {
                let summary = try clipboard.restoreBackup(from: url)
                print("restored backup: \(summary)")
            } catch {
                print("cannot restore backup: \(error)")
            }
        }
        if let url = arguments.exportBackup {
            do {
                try clipboard.exportBackup(to: url)
            } catch {
                print("cannot export backup: \(error)")
            }
        }
        if let tool = arguments.transform {
            clipboard.transformNewestText(withToolNamed: tool)
        }
        if let format = arguments.copyColor {
            clipboard.copyNewestColor(asFormatNamed: format)
        }
        if arguments.showsDropTargets {
            files.showDropTargets()
        }
        if !arguments.droppedFiles.isEmpty {
            files.add(arguments.droppedFiles)
        }
        if let action = arguments.fileAction {
            files.run(actionNamed: action)
        }
        if arguments.editNewestText {
            clipboard.editNewestText()
        }
        if arguments.copyStack {
            print("copy stack started: \(clipboard.toggleCopyStack())")
        }
        if let search = arguments.search {
            clipboard.setSearchText(search)
        }
        if arguments.openOnLaunch {
            controller.open()
        }
        if arguments.showLibrary {
            clipboard.showLibrary(filter: arguments.libraryFilter, layout: arguments.libraryLayout)
        }
        if arguments.showSettings {
            settingsWindow.show(tabID: arguments.settingsTab, query: arguments.settingsSearch)
        }
        // The guide comes up once, the first time the app is opened by hand.
        if arguments.showWelcome {
            welcome.show()
        } else if arguments.isPlainLaunch {
            welcome.showIfFirstRun()
        }
        if let pageID = arguments.selectedPage {
            controller.selectPage(id: pageID)
        }
        if arguments.editOverview {
            overview.beginEditing()
        }
        var settleTime: TimeInterval = 1.5
        if arguments.showClipboardPanel {
            // Pinned, so a click elsewhere during an automated check does not close it.
            clipboard.isPanelPinned = true
            clipboard.showPanel()
        }
        if let script = arguments.keyScript {
            settleTime = max(settleTime, KeyScript.run(script, clipboard: clipboard) + 0.6)
        }
        // Simulated system events, 0.2 s apart; the snapshot waits until after the last one.
        for (index, name) in arguments.simulatedEvents.enumerated() {
            guard let event = SimulatedSystemEvent(rawValue: name) else { continue }
            let delay = 0.5 + Double(index) * 0.2
            settleTime = max(settleTime, delay + 0.7)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                systemEvents.simulate(event)
            }
        }
        if let directory = arguments.snapshotDirectory {
            // Wait for animations and scripted keys to settle before drawing.
            DispatchQueue.main.asyncAfter(deadline: .now() + settleTime) {
                WindowSnapshot.writeAll(to: directory)
            }
        }
    }

    private static var defaultDataDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AraNotch/Clipboard", isDirectory: true)
    }
}
