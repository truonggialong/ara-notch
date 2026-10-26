import SwiftUI

/// The app's icons, by what they mean. Every control that could be a word is one of these
/// instead, and its name is what the tooltip and VoiceOver say.
public enum AraIcon: String, CaseIterable, Sendable {
    // Pages
    case clipboard, music, timer, calendar, files, agents, about, settings
    // Finding and arranging
    case search, clear, close, confirm, add, remove, saveFilter, grid, list, more, preview, back, forward
    case enlarge, shrink
    // Clips
    case newNote, copyStack, copyStackOn, pin, unpin, copy, paste, pastePlain, edit, delete
    case open, openWith, openLink, showInFinder, link, remind, removeBackground, savePicture, readText, assistant
    case text, code, color, picture, document, locked, unlocked, touchID
    // Files
    case convert, resize, compress, pdf, airDrop, reveal
    // Playback
    case previous, next, play, pause, stop, reset, output
    // Calendar
    case join, complete, completed, reminders, today
    // Capture and annotation
    case captureRegion, captureScroll, pickColor, arrow, line, rectangle, ellipse, highlight, draw, typeText
    case step, blur, undo, redo, save
    // Translation
    case translate, replace, speak, swapLanguage
    // States
    case idle, working, waiting, done, warning, muted, recording, paused

    /// The system symbol drawn for the icon.
    public var symbolName: String {
        switch self {
        case .clipboard: "doc.on.clipboard"
        case .music: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        case .files: "tray.and.arrow.down"
        case .agents: "terminal"
        case .about: "info.circle"
        case .settings: "gearshape"
        case .search: "magnifyingglass"
        case .clear: "xmark.circle.fill"
        case .close: "xmark"
        case .confirm: "checkmark"
        case .add: "plus"
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .remove: "minus"
        case .saveFilter: "bookmark"
        case .grid: "square.grid.2x2"
        case .list: "list.bullet"
        case .more: "ellipsis"
        case .preview: "eye"
        case .newNote: "square.and.pencil"
        case .copyStack: "square.stack.3d.up"
        case .copyStackOn: "square.stack.3d.up.fill"
        case .pin: "pin.fill"
        case .unpin: "pin.slash"
        case .copy: "doc.on.doc"
        case .paste: "arrow.down.doc"
        case .pastePlain: "textformat"
        case .edit: "pencil"
        case .delete: "trash"
        case .open: "arrow.up.forward.square"
        case .openWith: "arrow.up.forward.app"
        case .openLink: "safari"
        case .showInFinder: "folder"
        case .link: "link"
        case .remind: "bell"
        case .removeBackground: "person.and.background.dotted"
        case .savePicture: "square.and.arrow.down"
        case .readText: "text.viewfinder"
        case .assistant: "sparkles"
        case .text: "text.alignleft"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .color: "paintpalette"
        case .picture: "photo"
        case .document: "doc"
        case .locked: "lock.fill"
        case .unlocked: "lock.open.fill"
        case .touchID: "touchid"
        case .convert: "arrow.triangle.2.circlepath"
        case .resize: "arrow.down.right.and.arrow.up.left"
        case .enlarge: "arrow.up.left.and.arrow.down.right"
        case .shrink: "arrow.down.right.and.arrow.up.left"
        case .compress: "rectangle.compress.vertical"
        case .pdf: "doc.richtext"
        case .airDrop: "dot.radiowaves.left.and.right"
        case .reveal: "folder"
        case .previous: "backward.fill"
        case .next: "forward.fill"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .stop: "stop.fill"
        case .reset: "arrow.counterclockwise"
        case .output: "speaker.wave.2.fill"
        case .join: "video.fill"
        case .complete: "circle"
        case .completed: "checkmark.circle.fill"
        case .reminders: "checklist"
        case .today: "calendar"
        case .captureRegion: "viewfinder"
        case .captureScroll: "arrow.up.and.down.text.horizontal"
        case .pickColor: "eyedropper"
        case .arrow: "arrow.up.right"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .step: "1.circle"
        case .blur: "checkerboard.rectangle"
        case .highlight: "highlighter"
        case .draw: "scribble.variable"
        case .typeText: "character.cursor.ibeam"
        case .undo: "arrow.uturn.backward"
        case .redo: "arrow.uturn.forward"
        case .save: "square.and.arrow.down"
        case .translate: "character.bubble"
        case .replace: "arrow.left.arrow.right"
        case .speak: "speaker.wave.2"
        case .swapLanguage: "arrow.triangle.2.circlepath"
        case .idle: "circle"
        case .working: "gearshape.2.fill"
        case .waiting: "exclamationmark.bubble.fill"
        case .done: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle"
        case .muted: "speaker.slash"
        case .recording: "record.circle"
        case .paused: "pause.circle"
        }
    }

    /// The key of the icon's name in the strings files.
    public var labelKey: String {
        "icon.\(rawValue)"
    }

    /// What the icon means, in the user's language: its tooltip and its VoiceOver name.
    public var label: String {
        L10n.string(labelKey)
    }

    public var image: Image {
        Image(systemName: symbolName)
    }
}
