import Foundation

/// Command-line switches, used by automated checks to put the app into a known state.
struct LaunchArguments {
    /// `--open-on-launch`: open the notch right away.
    let openOnLaunch: Bool
    /// `--show-in-dock`: run as a regular app with a Dock icon, so UI automation tools can see it.
    let showInDock: Bool
    /// `--show-settings`: show the Settings window right away.
    let showSettings: Bool
    /// `--simulate-sounding <bundle ids, comma separated>`: show these apps as sending sound.
    let simulatedSoundingApps: [String]
    /// `--show-welcome`: show the first-run guide, whether or not it was shown before.
    let showWelcome: Bool
    /// The app was opened with no options at all: by hand, not by a check.
    let isPlainLaunch: Bool
    /// `--settings-tab <id>`: with `--show-settings`, the tab to open (`general`, `clipboard`, `alerts`).
    let settingsTab: String?
    /// `--settings-search <text>`: with `--show-settings`, type this in the search field.
    let settingsSearch: String?
    /// `--seed-clipboard`: add a fixed set of sample clips.
    let seedClipboard: Bool
    /// `--seed-boards`: with `--seed-clipboard`, create two boards and pin some sample clips.
    let seedBoards: Bool
    /// `--seed-vault <passcode>`: with `--seed-boards`, lock the "Công việc" board with this passcode.
    let seedVaultPasscode: String?
    /// `--unlock-vault <passcode>`: unlock the vault right away.
    let unlockVaultPasscode: String?
    /// `--select-board <name>`: show this board on the clipboard page.
    let selectedBoard: String?
    /// `--edit-new-board`: open the editor for a new board.
    let editNewBoard: Bool
    /// `--select-page <id>`
    let selectedPage: String?
    /// `--overview-arrangement <tiles>`: show the overview with these tiles, comma separated as
    /// `<widget>:<size>` (`media:large,timer:small`), without saving them or any change to them.
    let overviewArrangement: [String]?
    /// `--edit-overview`: start with the overview's tiles being arranged.
    let editOverview: Bool
    /// `--search <text>`: pre-fill the clipboard search field.
    let search: String?
    /// `--transform <tool>`: apply a text tool (a `TextTransform` case name) to the newest text clip.
    let transform: String?
    /// `--restore-backup <path>`: merge this backup file into the history right away.
    let restoreBackup: URL?
    /// `--export-backup <path>`: write a backup file once the other launch arguments were applied.
    let exportBackup: URL?
    /// `--copy-color <format>`: copy the newest colour clip as `hex`, `rgb` or `hsl`.
    let copyColor: String?
    /// `--simulate-now-playing <json>`: show this track instead of asking the system; one line
    /// in the format of the now-playing helper.
    let simulatedNowPlaying: String?
    /// `--print-audio-outputs <file>`: write the list of sound output devices to this file.
    let audioOutputsFile: URL?
    /// `--drop-files <paths>`: comma-separated files to put on the Files page, as if dropped.
    let droppedFiles: [URL]
    /// `--show-drop-targets`: the Files page as it looks while files are dragged over it.
    let showsDropTargets: Bool
    /// `--file-action <name>`: run an action on those files; see `FilesController.run(actionNamed:)`.
    let fileAction: String?
    /// `--agent-events-file <path>`: read agent hook events from this file instead of the standard one.
    let agentEventsFile: URL?
    /// `--claude-settings <path>`: treat this file as Claude Code's settings (for testing the hook installer).
    let claudeSettingsFile: URL?
    /// `--uninstall-home <dir>`: removing AraNotch works on this folder as if it were the home
    /// folder, and leaves the login item, the settings and the app itself alone; for trying it.
    let uninstallHome: URL?
    /// `--install-claude-hooks` / `--remove-claude-hooks`: do what the buttons in Settings do.
    let installClaudeHooks: Bool
    let removeClaudeHooks: Bool
    /// `--snap <zone>`: snap the front window to a `SnapZone` a second after launch.
    let snapZone: String?
    /// `--copy-stack`: start the copy stack right away.
    let copyStack: Bool
    /// `--translate <text>`: translate this text and show the panel. Sends the text to Google Translate.
    let translateText: String?
    /// `--show-library`: show the Library window right away.
    let showLibrary: Bool
    /// `--library-filter <filter>`: with `--show-library`: `kind:<kind>`, `app:<name>` or `board:<name>`.
    let libraryFilter: String?
    /// `--library-layout <grid|list>`: with `--show-library`.
    let libraryLayout: String?
    /// `--data-dir <path>`: keep the clipboard history here instead of Application Support.
    let dataDirectory: URL?
    /// `--pasteboard-name <name>`: watch this named pasteboard instead of the general one.
    let pasteboardName: String?
    /// `--show-clipboard-panel`: show the floating clipboard panel right away, pinned open.
    let showClipboardPanel: Bool
    /// `--send-keys <script>`: key presses to feed to the clipboard panel; see `KeyScript`.
    let keyScript: String?
    /// `--allow-local-link-previews`: let link previews be fetched from this machine (testing).
    let allowLocalLinkPreviews: Bool
    /// `--simulate-events <list>`: comma-separated system events to show as if they happened
    /// (`plug`, `unplug`, `low`, `full`, `caps-on`, `caps-off`, `offline`, `online`).
    let simulatedEvents: [String]
    /// `--no-hardware-notch`: lay the notch out as if the display had no hardware notch.
    let noHardwareNotch: Bool
    /// `--claude-usage-file <path>`: read Claude's rate limits from this file.
    let claudeUsageFile: URL?
    /// `--codex-sessions-dir <path>`: read Codex session logs from this folder.
    let codexSessionsDirectory: URL?
    /// `--install-claude-statusline` / `--remove-claude-statusline`: change the status line in `--claude-settings`.
    let installClaudeStatusLine: Bool
    let removeClaudeStatusLine: Bool
    /// `--print-agents <file>`: write what the app knows about agents (sessions, rate limits) after a moment.
    let agentSummaryFile: URL?
    /// `--new-note`: make a new note in Notes and open it on the notch.
    let newNote: Bool
    /// `--show-notes`: open the notch on the Notes page right away.
    let showNotes: Bool
    /// `--dump-note-data <note id> <file>`: write the note's raw database body to the file (needs Full Disk Access).
    let dumpNoteData: (id: String, file: URL)?
    /// `--append-note <note id> <text> <report file>`: add a paragraph to the note and save it, as typing would.
    let appendNote: (id: String, text: String, report: URL)?
    /// `--self-test-notes <report file>`: drive the Notes window with key and mouse events, then quit (see `runSelfTest`).
    let selfTestNotes: URL?
    /// `--check-reminders <file>`: write whether a reminder can be made (one is made and removed at once).
    let checkRemindersFile: URL?
    /// `--cut-out <image>`: cut the picture's subject out and write the PNG to `--capture-out`.
    let cutOutFile: URL?
    /// `--pick-color`: show the colour loupe a second after launch.
    let pickColor: Bool
    /// `--edit-newest-text`: open the editor window for the newest text clip.
    let editNewestText: Bool
    /// `--capture-rect <x,y,w,h>`: capture this rectangle of the screen and open it in the editor.
    let captureRect: CGRect?
    /// `--capture-scroll`: with `--capture-rect`, make it a scrolling capture.
    let captureScrolls: Bool
    /// `--annotate <image>`: open this picture in the capture editor.
    let annotateFile: URL?
    /// `--ocr <image>`: read the text in this picture and write it to `--capture-out`.
    let ocrFile: URL?
    /// `--render-sample <image>`: draw sample annotations into this picture and write it to `--capture-out`.
    let renderSampleFile: URL?
    /// `--capture-out <file>`: where `--ocr` and `--render-sample` write.
    let captureOutput: URL?
    /// `--selection-bar <text>`: show the Smart Selection bar for this text at the pointer.
    let selectionBarText: String?
    /// `--simulate-agenda`: fill the calendar page with made-up events and reminders around
    /// the current time, without reading the real calendars.
    let simulateAgenda: Bool
    /// Opens the calendar page on one of its pickers ("day", "event" or "reminder"), for automated checks.
    let calendarPicker: String?
    /// `--update-feed <url>`: read updates from this feed (a file or an https address)
    /// instead of the published one, for trying an update before it is released.
    let updateFeed: String?
    /// `--check-updates`: look for an update right after launch.
    let checkUpdates: Bool
    /// `--print-agenda <file>`: write how many events and reminders the app can read (counts only).
    let agendaSummaryFile: URL?
    /// `--timer <seconds>`: start a countdown right away.
    /// Countdowns to start at launch, in seconds; several are separated by commas.
    let timerSeconds: [TimeInterval]
    /// `--snapshot-dir <path>`: render this app's own windows to PNG files in this directory.
    let snapshotDirectory: URL?

    init(_ arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        openOnLaunch = arguments.contains("--open-on-launch")
        showSettings = arguments.contains("--show-settings")
        simulatedSoundingApps = (value(after: "--simulate-sounding") ?? "").split(separator: ",").map(String.init)
        showWelcome = arguments.contains("--show-welcome")
        isPlainLaunch = !arguments.dropFirst().contains { $0.hasPrefix("--") }
        showInDock = arguments.contains("--show-in-dock")
        seedClipboard = arguments.contains("--seed-clipboard")
        seedBoards = arguments.contains("--seed-boards")
        claudeUsageFile = value(after: "--claude-usage-file").map { URL(fileURLWithPath: $0) }
        codexSessionsDirectory = value(after: "--codex-sessions-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
        installClaudeStatusLine = arguments.contains("--install-claude-statusline")
        removeClaudeStatusLine = arguments.contains("--remove-claude-statusline")
        agentSummaryFile = value(after: "--print-agents").map { URL(fileURLWithPath: $0) }
        newNote = arguments.contains("--new-note")
        showNotes = arguments.contains("--show-notes")
        dumpNoteData = arguments.firstIndex(of: "--dump-note-data").flatMap { index in
            arguments.indices.contains(index + 2) ? (arguments[index + 1], URL(fileURLWithPath: arguments[index + 2])) : nil
        }
        appendNote = arguments.firstIndex(of: "--append-note").flatMap { index in
            arguments.indices.contains(index + 3)
                ? (arguments[index + 1], arguments[index + 2], URL(fileURLWithPath: arguments[index + 3])) : nil
        }
        selfTestNotes = value(after: "--self-test-notes").map { URL(fileURLWithPath: $0) }
        checkRemindersFile = value(after: "--check-reminders").map { URL(fileURLWithPath: $0) }
        cutOutFile = value(after: "--cut-out").map { URL(fileURLWithPath: $0) }
        pickColor = arguments.contains("--pick-color")
        editNewestText = arguments.contains("--edit-newest-text")
        captureScrolls = arguments.contains("--capture-scroll")
        noHardwareNotch = arguments.contains("--no-hardware-notch")
        captureRect = value(after: "--capture-rect").flatMap { text -> CGRect? in
            let parts = text.split(separator: ",").compactMap { Double($0) }
            return parts.count == 4 ? CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
        }
        annotateFile = value(after: "--annotate").map { URL(fileURLWithPath: $0) }
        ocrFile = value(after: "--ocr").map { URL(fileURLWithPath: $0) }
        renderSampleFile = value(after: "--render-sample").map { URL(fileURLWithPath: $0) }
        captureOutput = value(after: "--capture-out").map { URL(fileURLWithPath: $0) }
        selectionBarText = value(after: "--selection-bar")
        simulateAgenda = arguments.contains("--simulate-agenda")
        calendarPicker = value(after: "--calendar-picker")
        updateFeed = value(after: "--update-feed")
        checkUpdates = arguments.contains("--check-updates")
        agendaSummaryFile = value(after: "--print-agenda").map { URL(fileURLWithPath: $0) }
        timerSeconds = (value(after: "--timer") ?? "").split(separator: ",").compactMap { TimeInterval($0) }
        selectedBoard = value(after: "--select-board")
        seedVaultPasscode = value(after: "--seed-vault")
        unlockVaultPasscode = value(after: "--unlock-vault")
        editNewBoard = arguments.contains("--edit-new-board")
        showClipboardPanel = arguments.contains("--show-clipboard-panel")
        allowLocalLinkPreviews = arguments.contains("--allow-local-link-previews")
        simulatedEvents = (value(after: "--simulate-events") ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        keyScript = value(after: "--send-keys")
        selectedPage = value(after: "--select-page")
        overviewArrangement = value(after: "--overview-arrangement")?.split(separator: ",").map(String.init)
        editOverview = arguments.contains("--edit-overview")
        settingsTab = value(after: "--settings-tab")
        settingsSearch = value(after: "--settings-search")
        search = value(after: "--search")
        transform = value(after: "--transform")
        translateText = value(after: "--translate")
        copyStack = arguments.contains("--copy-stack")
        snapZone = value(after: "--snap")
        agentEventsFile = value(after: "--agent-events-file").map { URL(fileURLWithPath: $0) }
        claudeSettingsFile = value(after: "--claude-settings").map { URL(fileURLWithPath: $0) }
        uninstallHome = value(after: "--uninstall-home").map { URL(fileURLWithPath: $0, isDirectory: true) }
        installClaudeHooks = arguments.contains("--install-claude-hooks")
        removeClaudeHooks = arguments.contains("--remove-claude-hooks")
        showsDropTargets = arguments.contains("--show-drop-targets")
        droppedFiles = (value(after: "--drop-files") ?? "").split(separator: ",").map { URL(fileURLWithPath: String($0)) }
        fileAction = value(after: "--file-action")
        audioOutputsFile = value(after: "--print-audio-outputs").map { URL(fileURLWithPath: $0) }
        simulatedNowPlaying = value(after: "--simulate-now-playing")
        copyColor = value(after: "--copy-color")
        showLibrary = arguments.contains("--show-library")
        libraryFilter = value(after: "--library-filter")
        libraryLayout = value(after: "--library-layout")
        restoreBackup = value(after: "--restore-backup").map { URL(fileURLWithPath: $0) }
        exportBackup = value(after: "--export-backup").map { URL(fileURLWithPath: $0) }
        dataDirectory = value(after: "--data-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
        pasteboardName = value(after: "--pasteboard-name")
        snapshotDirectory = value(after: "--snapshot-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}
