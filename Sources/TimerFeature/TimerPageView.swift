import NotchShell
import SwiftUI
import TimerCore

/// The timer page of the notch: the choice of a length, one countdown writ large, or several
/// side by side.
struct TimerPageView: View {
    @Environment(\.araScale) private var ui
    @ObservedObject var model: TimerViewModel
    @ObservedObject var settings: TimerSettings

    var body: some View {
        if model.isChoosing {
            setup
        } else if model.board.entries.count == 1, let entry = model.board.entries.first {
            single(entry)
        } else {
            grid
        }
    }

    // MARK: - Choosing a length

    /// The length is set by sight: minutes round the face, hours inside it, or one of the
    /// lengths kept for a click. Nothing needs typing; the label is optional.
    private var setup: some View {
        HStack(alignment: .center, spacing: 18 * ui) {
            AraLengthDial(seconds: $settings.seconds)
            VStack(alignment: .leading, spacing: 7 * ui) {
                HStack(spacing: 5 * ui) {
                    ForEach(settings.presets, id: \.self) { minutes in
                        AraChip(isSelected: settings.seconds == minutes * 60) {
                            settings.seconds = minutes * 60
                        } label: {
                            Text(String(format: L10n.string("timer.minutes.short"), minutes))
                                .font(.system(size: 11 * ui, weight: .medium))
                                .monospacedDigit()
                        }
                        .contextMenu {
                            if settings.presets.count > 1 {
                                Button(role: .destructive) {
                                    settings.removePreset(minutes)
                                } label: {
                                    Label(L10n.string("timer.preset.remove"), systemImage: AraIcon.delete.symbolName)
                                }
                            }
                        }
                    }
                    // The length on show becomes a preset with one click, while there is room. The
                    // button keeps its place when it cannot be used, so the row does not shift.
                    let canAdd = settings.canAddCurrentAsPreset && settings.length.wholeMinutes != nil
                    AraIconButton(
                        .saveFilter, size: .small,
                        help: canAdd ? String(format: L10n.string("timer.preset.add"), settings.length.wholeMinutes ?? 0) : nil
                    ) {
                        settings.addCurrentAsPreset()
                    }
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : 0.3)
                }
                HStack(spacing: 8 * ui) {
                    Text(TimerFormat.clock(TimeInterval(settings.seconds)))
                        .font(.system(size: 28 * ui, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .frame(minWidth: 96 * ui, alignment: .leading)
                    // Seconds have no ring of their own: two buttons step them.
                    HStack(spacing: 2 * ui) {
                        AraIconButton(.remove, look: .bare, size: .small, help: L10n.string("timer.seconds.less")) {
                            settings.turn(.seconds, by: -5)
                        }
                        Text(L10n.string("timer.unit.seconds"))
                            .font(.system(size: 10 * ui, weight: .medium))
                            .foregroundStyle(AraTheme.secondaryText)
                        AraIconButton(.add, look: .bare, size: .small, help: L10n.string("timer.seconds.more")) {
                            settings.turn(.seconds, by: 5)
                        }
                    }
                    .padding(.horizontal, 2 * ui)
                    .araSurface(Capsule())
                    AraIconButton(.play, look: .accent, size: .large, help: L10n.string("timer.start")) {
                        model.onStart?(settings.seconds)
                    }
                    // Back to the countdowns under way without starting another.
                    if model.isAdding {
                        AraIconButton(.close, size: .large, help: L10n.string("settings.cancel")) {
                            model.isAdding = false
                        }
                    }
                }
                TextField(L10n.string("timer.label.placeholder"), text: $settings.label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11 * ui))
                    .padding(.horizontal, 10 * ui)
                    .frame(width: 240 * ui, height: 22 * ui)
                    .araSurface(Capsule())
            }
        }
    }

    // MARK: - One countdown

    @ViewBuilder
    private func single(_ entry: TimerBoard.Entry) -> some View {
        if entry.timer.phase == .finished {
            VStack(spacing: 9 * ui) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 18 * ui))
                    .foregroundStyle(AraPalette.warning)
                    .frame(width: 42 * ui, height: 42 * ui)
                    .araSurface(Circle(), level: .raised)
                Text(entry.label.isEmpty ? L10n.string("timer.finished.title") : entry.label)
                    .font(.system(size: 14 * ui, weight: .semibold))
                AraIconButton(.reset, look: .accent, size: .large, help: L10n.string("timer.reset")) {
                    model.onCancel?(entry.id)
                }
            }
        } else {
            let isPaused = isPaused(entry)
            VStack(spacing: 7 * ui) {
                if !entry.label.isEmpty {
                    Text(entry.label)
                        .font(.system(size: 11 * ui, weight: .medium))
                        .foregroundStyle(AraTheme.secondaryText)
                        .lineLimit(1)
                }
                Text(TimerFormat.clock(entry.timer.remaining(at: model.now)))
                    .font(.system(size: 42 * ui, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(isPaused ? 0.55 : 1)
                AraProgressLine(fraction: entry.timer.progress(at: model.now))
                    .frame(width: 300 * ui)
                HStack(spacing: 10 * ui) {
                    extendChip(entry, minutes: 1)
                    extendChip(entry, minutes: 5)
                    pauseButton(entry, size: .large)
                    AraIconButton(.stop, look: .danger, size: .large, help: L10n.string("settings.cancel")) {
                        model.onCancel?(entry.id)
                    }
                    AraIconButton(.add, size: .large, help: L10n.string("timer.add")) {
                        model.isAdding = true
                    }
                }
            }
        }
    }

    // MARK: - Several countdowns

    private var grid: some View {
        let columns = [GridItem(.flexible(), spacing: 8 * ui), GridItem(.flexible(), spacing: 8 * ui)]
        return LazyVGrid(columns: columns, spacing: 8 * ui) {
            ForEach(model.board.entries) { entry in
                tile(entry)
            }
            if !model.board.isFull {
                Button {
                    model.isAdding = true
                } label: {
                    Label(L10n.string("timer.add"), systemImage: AraIcon.add.symbolName)
                        .font(.system(size: 11 * ui, weight: .medium))
                        .foregroundStyle(AraTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.tileHeight * ui)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AraPressStyle(depth: 0.97))
                .araSurface(RoundedRectangle(cornerRadius: AraTheme.rowRadius * ui, style: .continuous))
            }
        }
    }

    private static let tileHeight: CGFloat = 62

    private func tile(_ entry: TimerBoard.Entry) -> some View {
        let isFinished = entry.timer.phase == .finished
        return HStack(spacing: 8 * ui) {
            VStack(alignment: .leading, spacing: 3 * ui) {
                HStack(spacing: 5 * ui) {
                    if isFinished {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10 * ui))
                            .foregroundStyle(AraPalette.warning)
                    }
                    Text(isFinished && entry.label.isEmpty ? L10n.string("timer.finished.short") : entry.label)
                        .font(.system(size: 10 * ui, weight: .medium))
                        .foregroundStyle(isFinished ? AraPalette.warning : AraTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(height: 12 * ui)
                Text(TimerFormat.clock(entry.timer.remaining(at: model.now)))
                    .font(.system(size: 20 * ui, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .opacity(isPaused(entry) || isFinished ? 0.55 : 1)
                AraProgressLine(fraction: entry.timer.progress(at: model.now))
            }
            if isFinished {
                AraIconButton(.reset, look: .accent, size: .small, help: L10n.string("timer.reset")) {
                    model.onCancel?(entry.id)
                }
            } else {
                extendChip(entry, minutes: 1)
                pauseButton(entry, size: .small)
                AraIconButton(.stop, look: .bareDanger, size: .small, help: L10n.string("settings.cancel")) {
                    model.onCancel?(entry.id)
                }
            }
        }
        .padding(.horizontal, 10 * ui)
        .frame(height: Self.tileHeight * ui)
        .araCard(radius: AraTheme.rowRadius)
    }

    // MARK: - Shared pieces

    private func isPaused(_ entry: TimerBoard.Entry) -> Bool {
        if case .paused = entry.timer.phase { return true }
        return false
    }

    @ViewBuilder
    private func pauseButton(_ entry: TimerBoard.Entry, size: AraButtonSize) -> some View {
        if isPaused(entry) {
            AraIconButton(.play, look: .accent, size: size, help: L10n.string("timer.resume")) {
                model.onResume?(entry.id)
            }
        } else {
            AraIconButton(.pause, size: size, help: L10n.string("timer.pause")) { model.onPause?(entry.id) }
        }
    }

    /// Adds a minute or five to a countdown under way.
    private func extendChip(_ entry: TimerBoard.Entry, minutes: Int) -> some View {
        AraChip(isSelected: false) {
            model.onExtend?(entry.id, minutes * 60)
        } label: {
            Text(String(format: L10n.string("timer.extend"), minutes))
                .font(.system(size: 11 * ui, weight: .medium))
                .monospacedDigit()
        }
    }
}
