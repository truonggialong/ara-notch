import NotchCore
import NotchShell
import SwiftUI
import TimerCore

/// The countdowns as a widget of the overview. Small: the one ending soonest, its time left
/// large, a click pauses or resumes it. Wide: its name and length, a minute more, pause, cancel.
/// Large: every countdown with its bar, the one-click lengths and a new one. Orange in the last
/// minute and once it has ended.
struct TimerWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    @ObservedObject var model: TimerViewModel
    @ObservedObject var settings: TimerSettings
    let onOpen: () -> Void

    private var soonest: TimerBoard.Entry? {
        model.board.soonest(at: model.now) ?? model.board.entries.first
    }

    var body: some View {
        AraWidget(
            name: L10n.string("page.timer.title"), hue: .mint, onOpen: openAction,
            actionName: size == .small ? soonest.map { L10n.string(actionKey($0)) } : nil
        ) {
            if model.board.entries.isEmpty {
                presets
            } else {
                switch size {
                case .small: small
                case .wide: wide
                case .large: large
                }
            }
        }
    }

    /// A small widget's click is the soonest countdown's pause and resume; the others open the page.
    private var openAction: () -> Void {
        guard size == .small, let entry = soonest else { return onOpen }
        return { toggle(entry) }
    }

    private func toggle(_ entry: TimerBoard.Entry) {
        if entry.timer.phase == .finished {
            model.onCancel?(entry.id)
        } else if isPaused(entry) {
            model.onResume?(entry.id)
        } else {
            model.onPause?(entry.id)
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 6 * ui) {
            AraWidgetHeader(label: L10n.string("widget.timer.label"))
            Spacer(minLength: 0)
            HStack(spacing: 5 * ui) {
                ForEach(settings.presets.prefix(size == .small ? 2 : size == .wide ? 3 : 4), id: \.self) { minutes in
                    presetButton(minutes)
                }
                if size == .large {
                    newButton
                }
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 2 * ui) {
            if let entry = soonest {
                AraWidgetHeader(label: L10n.string("widget.timer.label"), chip: chip(entry))
                Spacer(minLength: 0)
                AraBigValue(clock(entry), size: 24, isAlert: isAlert(entry))
                bar(entry)
            }
        }
    }

    private var wide: some View {
        VStack(alignment: .leading, spacing: 3 * ui) {
            if let entry = soonest {
                AraWidgetHeader(label: title(entry), chip: chip(entry))
                HStack(spacing: 5 * ui) {
                    AraBigValue(clock(entry), size: 26, isAlert: isAlert(entry))
                    Spacer(minLength: 4 * ui)
                    buttons(entry)
                }
                bar(entry)
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 5 * ui) {
            let running = model.board.entries.filter { if case .running = $0.timer.phase { true } else { false } }.count
            AraWidgetHeader(
                label: L10n.string("widget.timer.label"),
                chip: running > 0 ? AraStatusChip(text: String(format: L10n.string("widget.timer.count"), running), hue: .mint) : nil)
            ForEach(model.board.entries.prefix(TimerBoard.capacity)) { entry in
                VStack(alignment: .leading, spacing: 2 * ui) {
                    HStack(spacing: 6 * ui) {
                        Text(title(entry))
                            .font(.system(size: 10.5 * ui))
                            .foregroundStyle(AraPalette.widgetSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4 * ui)
                        Text(clock(entry))
                            .font(.system(size: 13 * ui, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(isAlert(entry) ? AraPalette.alert : AraPalette.widgetText)
                            .opacity(isPaused(entry) ? 0.55 : 1)
                    }
                    bar(entry)
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(entry) }
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text(L10n.string(actionKey(entry)))) { toggle(entry) }
            }
            Spacer(minLength: 0)
            if !model.board.isFull {
                HStack(spacing: 5 * ui) {
                    ForEach(settings.presets.prefix(3), id: \.self) { presetButton($0) }
                    newButton
                }
            }
        }
    }

    private func presetButton(_ minutes: Int) -> some View {
        Button {
            model.onStart?(minutes * 60)
        } label: {
            Text("\(minutes)′")
                .font(.system(size: 11 * ui, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AraPalette.vivid(.mint))
                .padding(.horizontal, 9 * ui)
                .frame(height: 24 * ui)
                .background(Capsule().fill(AraPalette.widgetQuiet))
                .fixedSize()
        }
        .buttonStyle(AraPressStyle())
    }

    /// Opens the timer page ready to set a new countdown.
    private var newButton: some View {
        Button {
            model.isAdding = true
            onOpen()
        } label: {
            Text(L10n.string("widget.timer.new"))
                .font(.system(size: 11 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.widgetText)
                .padding(.horizontal, 9 * ui)
                .frame(height: 24 * ui)
                .background(Capsule().fill(AraPalette.widgetQuiet))
                .fixedSize()
        }
        .buttonStyle(AraPressStyle())
    }

    @ViewBuilder
    private func buttons(_ entry: TimerBoard.Entry) -> some View {
        if entry.timer.phase == .finished {
            AraRoundButton(icon: .reset, label: L10n.string("timer.reset"), isPrimary: true, hue: .mint) {
                model.onCancel?(entry.id)
            }
        } else {
            AraRoundButton(icon: .add, label: L10n.string("widget.timer.addMinute"), hue: .mint) {
                model.onExtend?(entry.id, 60)
            }
            AraRoundButton(
                icon: isPaused(entry) ? .play : .pause, label: L10n.string(isPaused(entry) ? "timer.resume" : "timer.pause"),
                isPrimary: true, hue: .mint
            ) { toggle(entry) }
            AraRoundButton(icon: .close, label: L10n.string("timer.reset"), hue: .mint) {
                model.onCancel?(entry.id)
            }
        }
    }

    private func chip(_ entry: TimerBoard.Entry) -> AraStatusChip {
        let key = entry.timer.phase == .finished ? "widget.timer.finished" : isPaused(entry) ? "widget.timer.paused" : "widget.timer.running"
        return AraStatusChip(text: L10n.string(key), hue: .mint, isAlert: entry.timer.phase == .finished)
    }

    /// "Tea · 5:00": the countdown's name, if it has one, and its length.
    private func title(_ entry: TimerBoard.Entry) -> String {
        let length = TimerFormat.clock(entry.timer.duration)
        return entry.label.isEmpty ? length : "\(entry.label) · \(length)"
    }

    private func bar(_ entry: TimerBoard.Entry) -> some View {
        AraTrackBar(fraction: 1 - entry.timer.progress(at: model.now), hue: .mint, isAlert: isAlert(entry))
    }

    private func clock(_ entry: TimerBoard.Entry) -> String {
        entry.timer.phase == .finished ? L10n.string("timer.finished.short") : TimerFormat.clock(entry.timer.remaining(at: model.now))
    }

    private func isAlert(_ entry: TimerBoard.Entry) -> Bool {
        WidgetAlert.timer(remaining: entry.timer.remaining(at: model.now), isFinished: entry.timer.phase == .finished)
    }

    private func isPaused(_ entry: TimerBoard.Entry) -> Bool {
        if case .paused = entry.timer.phase { return true }
        return false
    }

    private func actionKey(_ entry: TimerBoard.Entry) -> String {
        entry.timer.phase == .finished ? "timer.reset" : isPaused(entry) ? "timer.resume" : "timer.pause"
    }
}
