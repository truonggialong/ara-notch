import AppKit
import NotchShell
import SwiftUI
import SystemEventsCore

/// The keep-awake settings, observable; every change is written through to the store.
@MainActor
public final class KeepAwakeSettings: ObservableObject {
    let store: KeepAwakeSettingsStore
    /// Called after any change, so a session running can follow it.
    var onChange: (() -> Void)?

    @Published public var allowsDisplaySleep: Bool { didSet { store.allowsDisplaySleep = allowsDisplaySleep; onChange?() } }
    @Published public var stopsOnLowBattery: Bool { didSet { store.stopsOnLowBattery = stopsOnLowBattery; onChange?() } }
    @Published public var lowBatteryPercent: Int { didSet { store.lowBatteryPercent = lowBatteryPercent; onChange?() } }
    @Published public var stopsWhenUnplugged: Bool { didSet { store.stopsWhenUnplugged = stopsWhenUnplugged; onChange?() } }
    @Published public var stopsOnSleep: Bool { didSet { store.stopsOnSleep = stopsOnSleep } }
    @Published public var remindsBeforeEnd: Bool { didSet { store.remindsBeforeEnd = remindsBeforeEnd } }
    @Published public var triggerApps: [String] { didSet { store.triggerApps = triggerApps; onChange?() } }
    @Published public var triggerDocked: Bool { didSet { store.triggerDocked = triggerDocked; onChange?() } }
    @Published public var triggerSchedule: Bool { didSet { store.triggerSchedule = triggerSchedule; onChange?() } }
    @Published public var scheduleDays: Set<Int> { didSet { store.scheduleDays = scheduleDays; onChange?() } }
    @Published public var scheduleStart: Int { didSet { store.scheduleStart = scheduleStart; onChange?() } }
    @Published public var scheduleEnd: Int { didSet { store.scheduleEnd = scheduleEnd; onChange?() } }

    public init(store: KeepAwakeSettingsStore) {
        self.store = store
        allowsDisplaySleep = store.allowsDisplaySleep
        stopsOnLowBattery = store.stopsOnLowBattery
        lowBatteryPercent = store.lowBatteryPercent
        stopsWhenUnplugged = store.stopsWhenUnplugged
        stopsOnSleep = store.stopsOnSleep
        remindsBeforeEnd = store.remindsBeforeEnd
        triggerApps = store.triggerApps
        triggerDocked = store.triggerDocked
        triggerSchedule = store.triggerSchedule
        scheduleDays = store.scheduleDays
        scheduleStart = store.scheduleStart
        scheduleEnd = store.scheduleEnd
    }
}

/// Settings › Tools › Keep awake: how it keeps the Mac awake, when it stops by itself, and the
/// Triggers that start it.
struct KeepAwakeSettingsSection: View {
    @ObservedObject var settings: KeepAwakeSettings

    var body: some View {
        Picker(selection: $settings.allowsDisplaySleep) {
            Text(L10n.string("keepAwake.withDisplay")).tag(false)
            Text(L10n.string("keepAwake.macOnly")).tag(true)
        } label: {
            Text(L10n.string("settings.keepAwake.display"))
            AraSettingsNote(L10n.string("settings.keepAwake.display.note"))
        }
        Picker(selection: Binding(
            get: { settings.stopsOnLowBattery ? settings.lowBatteryPercent : 0 },
            set: { percent in
                settings.stopsOnLowBattery = percent > 0
                if percent > 0 { settings.lowBatteryPercent = percent }
            }
        )) {
            Text(L10n.string("settings.off")).tag(0)
            ForEach(KeepAwakeSettingsStore.lowBatteryChoices, id: \.self) { percent in
                Text("\(percent)%").tag(percent)
            }
        } label: {
            Text(L10n.string("settings.keepAwake.lowBattery"))
        }
        Toggle(L10n.string("settings.keepAwake.unplugged"), isOn: $settings.stopsWhenUnplugged)
        Toggle(L10n.string("settings.keepAwake.sleep"), isOn: $settings.stopsOnSleep)
        Toggle(L10n.string("settings.keepAwake.remind"), isOn: $settings.remindsBeforeEnd)
        // Triggers.
        LabeledContent {
            TriggerAppsPicker(settings: settings)
        } label: {
            Text(L10n.string("settings.keepAwake.trigger.apps"))
            AraSettingsNote(L10n.string("settings.keepAwake.trigger.apps.note"))
        }
        Toggle(isOn: $settings.triggerDocked) {
            Text(L10n.string("settings.keepAwake.trigger.docked"))
            AraSettingsNote(L10n.string("settings.keepAwake.trigger.docked.note"))
        }
        Toggle(L10n.string("settings.keepAwake.trigger.schedule"), isOn: $settings.triggerSchedule)
        if settings.triggerSchedule {
            LabeledContent(L10n.string("settings.keepAwake.trigger.days")) {
                HStack(spacing: 4) {
                    // Monday first.
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                        let isOn = settings.scheduleDays.contains(day)
                        Button(Self.dayName(day)) {
                            if isOn { settings.scheduleDays.remove(day) } else { settings.scheduleDays.insert(day) }
                        }
                        .buttonStyle(.bordered)
                        .tint(isOn ? .accentColor : nil)
                        .controlSize(.small)
                    }
                }
            }
            LabeledContent(L10n.string("settings.keepAwake.trigger.hours")) {
                HStack {
                    DatePicker("", selection: time(\.scheduleStart), displayedComponents: .hourAndMinute).labelsHidden()
                    Text("–")
                    DatePicker("", selection: time(\.scheduleEnd), displayedComponents: .hourAndMinute).labelsHidden()
                }
            }
        }
    }

    private static func dayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        return symbols[(weekday - 1) % 7]
    }

    private func time(_ key: ReferenceWritableKeyPath<KeepAwakeSettings, Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(settings[keyPath: key] * 60)) },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings[keyPath: key] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}

/// The apps that keep the Mac awake while they run: their icons, each with a way to remove
/// it, and a menu of the apps open now to add one.
private struct TriggerAppsPicker: View {
    @ObservedObject var settings: KeepAwakeSettings

    var body: some View {
        HStack(spacing: 6) {
            ForEach(settings.triggerApps, id: \.self) { bundleID in
                Button {
                    settings.triggerApps.removeAll { $0 == bundleID }
                } label: {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                    } else {
                        Text(bundleID).font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .help(L10n.string("settings.keepAwake.trigger.remove"))
            }
            Menu {
                ForEach(Self.openApps(), id: \.bundleIdentifier) { app in
                    Button(app.localizedName ?? "") {
                        if let id = app.bundleIdentifier, !settings.triggerApps.contains(id) {
                            settings.triggerApps.append(id)
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    static func openApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

public extension KeepAwakeController {
    func makeSettingsSection() -> AnyView {
        AnyView(KeepAwakeSettingsSection(settings: settings))
    }

    /// The choices of a session, shown on the tools page when its button is held: lengths, a
    /// time of day on a clock face, an app that is open, or the downloads under way.
    func makeChooser(close: @escaping () -> Void) -> AnyView {
        AnyView(KeepAwakeChooser(controller: self, isDownloading: isDownloading(), close: close))
    }
}

/// The choices of a session.
private struct KeepAwakeChooser: View {
    let controller: KeepAwakeController
    let isDownloading: Bool
    let close: () -> Void
    @Environment(\.araScale) private var ui
    @StateObject private var state = ChooserState()

    var body: some View {
        HStack(alignment: .top, spacing: 14 * ui) {
            VStack(alignment: .leading, spacing: 8 * ui) {
                row {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        AraChip { pick { controller.keepAwake(minutes: minutes) } } label: {
                            Text(minutes < 60 ? "\(minutes)\u{2032}" : String(format: L10n.string("keepAwake.hours"), minutes / 60))
                        }
                    }
                    AraChip { pick { controller.keepAwake(minutes: nil) } } label: { Text("∞") }
                }
                row {
                    AraChip(isSelected: state.showsClock) { state.showsClock.toggle() } label: {
                        Text(L10n.string("keepAwake.untilTime"))
                    }
                    if isDownloading {
                        AraChip { pick { controller.keepAwakeUntilDownloadsFinish() } } label: {
                            Text(L10n.string("keepAwake.untilDownloads"))
                        }
                    }
                }
                Text(L10n.string("keepAwake.whileAppTitle"))
                    .font(.system(size: 10.5 * ui, weight: .medium))
                    .foregroundStyle(AraPalette.ink.opacity(0.6))
                row {
                    ForEach(TriggerAppsPicker.openApps().prefix(6), id: \.processIdentifier) { app in
                        Button { pick { controller.keepAwake(whileAppRuns: app) } } label: {
                            Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 22 * ui, height: 22 * ui)
                        }
                        .buttonStyle(AraPressStyle())
                        .help(app.localizedName ?? "")
                    }
                }
            }
            if state.showsClock {
                VStack(spacing: 6 * ui) {
                    AraClockFace(minutesOfDay: $state.minutes, diameter: 104)
                    AraChip(isSelected: true) { pick { controller.keepAwake(untilMinutesOfDay: state.minutes) } } label: {
                        Text(L10n.string("keepAwake.start"))
                    }
                }
            }
        }
        .padding(12 * ui)
        .background(RoundedRectangle(cornerRadius: 16 * ui, style: .continuous).fill(Color.black.opacity(0.92)))
        .overlay(RoundedRectangle(cornerRadius: 16 * ui, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6 * ui) { content() }
    }

    private func pick(_ action: () -> Void) {
        action()
        close()
    }
}

@MainActor
private final class ChooserState: ObservableObject {
    @Published var showsClock = false
    @Published var minutes: Int = {
        // An hour from now, on the quarter.
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(3600))
        return ((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) / 15 * 15
    }()
}
