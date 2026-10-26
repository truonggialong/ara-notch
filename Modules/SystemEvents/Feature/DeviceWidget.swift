import NotchCore
import NotchShell
import SwiftUI
import SystemEventsCore

/// The battery as the overview shows it.
@MainActor
final class BatteryModel: ObservableObject {
    @Published var snapshot = PowerSnapshot(hasBattery: false, isOnAC: true, isCharging: false, percent: 0)
}

/// The Mac's battery, as a widget of the overview. Small: the charge, large, as five segments,
/// and the time left. Wide: that, whether it is charging, and the volume with the speaker in
/// use. Large: a row for the Mac and for each Bluetooth device connected now, and the volume.
/// Orange for a battery at a fifth or less that is not charging.
struct DeviceWidget: View {
    @Environment(\.araScale) private var ui
    @Environment(\.araTileSize) private var size
    @ObservedObject var battery: BatteryModel
    @ObservedObject var reader: BluetoothBatteryReader
    let volume: AnyView

    var body: some View {
        let snapshot = battery.snapshot
        AraWidget(name: L10n.string("widget.device.title"), hue: .sage) {
            switch size {
            case .small: small(snapshot)
            case .wide: wide(snapshot)
            case .large: large(snapshot)
            }
        }
    }

    private func small(_ snapshot: PowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2 * ui) {
            AraWidgetHeader(label: L10n.string("widget.device.battery"), chip: timeChip(snapshot))
            Spacer(minLength: 0)
            if snapshot.hasBattery {
                AraBigValue("\(snapshot.percent)%", size: 24, isAlert: isLow(snapshot))
                AraSegmentBar(percent: snapshot.percent, hue: .sage, isAlert: isLow(snapshot))
            } else {
                mains
            }
        }
    }

    private func wide(_ snapshot: PowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4 * ui) {
            if snapshot.hasBattery {
                HStack(alignment: .center, spacing: 10 * ui) {
                    AraBigValue("\(snapshot.percent)%", size: 26, isAlert: isLow(snapshot))
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 4 * ui) {
                        AraWidgetHeader(
                            label: batteryLabel(snapshot),
                            chip: snapshot.isCharging ? AraStatusChip(text: L10n.string("widget.device.charging"), hue: .sage) : nil)
                        AraSegmentBar(percent: snapshot.percent, hue: .sage, isAlert: isLow(snapshot))
                    }
                }
            } else {
                AraWidgetHeader(label: L10n.string("widget.device.battery"))
                mains
            }
            Spacer(minLength: 0)
            volume
        }
    }

    private func large(_ snapshot: PowerSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5 * ui) {
            AraWidgetHeader(label: L10n.string("widget.device.title"), chip: timeChip(snapshot))
            deviceRow(
                symbol: snapshot.hasBattery ? "laptopcomputer" : "desktopcomputer", name: L10n.string("overview.device.thisMac"),
                percent: snapshot.hasBattery ? snapshot.percent : nil, isCharging: snapshot.isCharging,
                note: snapshot.hasBattery ? nil : L10n.string("widget.device.mains"))
            ForEach(Array(reader.devices.prefix(4).enumerated()), id: \.offset) { _, device in
                deviceRow(symbol: device.kind.symbolName, name: device.name, percent: device.percent, isCharging: false, note: nil)
            }
            Spacer(minLength: 0)
            volume
        }
        .onAppear { reader.refreshIfStale() }
        // While the page is on screen the report is read again every two minutes.
        .background {
            TimelineView(.periodic(from: .now, by: 120)) { context in
                Color.clear.onChange(of: context.date) { _, _ in reader.refreshIfStale() }
            }
        }
    }

    /// A device: its symbol, its name, its charge as a bar and a number. A device that reports
    /// no charge has neither.
    private func deviceRow(symbol: String, name: String, percent: Int?, isCharging: Bool, note: String?) -> some View {
        let isLow = WidgetAlert.battery(percent: percent, isCharging: isCharging)
        return HStack(spacing: 7 * ui) {
            Image(systemName: symbol)
                .font(.system(size: 11 * ui, weight: .semibold))
                .foregroundStyle(AraPalette.vivid(.sage))
                .frame(width: 18 * ui)
                .accessibilityHidden(true)
            Text(name)
                .font(.system(size: 11 * ui, weight: .semibold))
                .lineLimit(1)
                .frame(width: 92 * ui, alignment: .leading)
            if let percent {
                AraTrackBar(fraction: Double(percent) / 100, hue: .sage, isAlert: isLow)
                Text("\(percent)%")
                    .font(.system(size: 11 * ui, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isLow ? AraPalette.alert : AraPalette.widgetText)
                    .frame(width: 36 * ui, alignment: .trailing)
            } else {
                Text(note ?? "")
                    .font(.system(size: 10.5 * ui))
                    .foregroundStyle(AraPalette.widgetSecondary)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 15 * ui)
        .accessibilityElement(children: .combine)
    }

    private var mains: some View {
        Text(L10n.string("widget.device.mains"))
            .font(.system(size: 14 * ui, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func isLow(_ snapshot: PowerSnapshot) -> Bool {
        snapshot.hasBattery && WidgetAlert.battery(percent: snapshot.percent, isCharging: snapshot.isCharging)
    }

    /// "Battery · ~4 h left", or just "Battery · Mac" while the system has not worked it out.
    private func batteryLabel(_ snapshot: PowerSnapshot) -> String {
        guard let left = Self.timeLeft(snapshot) else { return L10n.string("widget.device.battery") }
        return L10n.string("widget.device.batteryShort") + " · " + String(format: L10n.string("widget.device.left"), left)
    }

    private func timeChip(_ snapshot: PowerSnapshot) -> AraStatusChip? {
        Self.timeLeft(snapshot).map { AraStatusChip(text: "~" + $0, hue: .sage) }
    }

    /// The time the battery has left, rounded: "25′", "4 h"; nil when not known or on mains power.
    private static func timeLeft(_ snapshot: PowerSnapshot) -> String? {
        guard snapshot.hasBattery, !snapshot.isOnAC, let minutes = snapshot.minutesLeft, minutes > 0 else { return nil }
        if minutes < 60 { return String(format: L10n.string("widget.duration.minutes"), minutes) }
        return String(format: L10n.string("widget.duration.hours"), Int((Double(minutes) / 60).rounded()))
    }
}
