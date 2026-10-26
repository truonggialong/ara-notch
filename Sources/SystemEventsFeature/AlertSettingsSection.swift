import NotchShell
import SwiftUI

/// The system's own notices in Settings › Notices: one chip each.
struct AlertSettingsSection: View {
    @ObservedObject var settings: AlertSettings

    var body: some View {
        AraChipRow(titleKey: "settings.alerts.system", chips: [
            .init(id: "power", title: L10n.string("settings.alerts.power"), isOn: $settings.power),
            .init(id: "capsLock", title: L10n.string("settings.alerts.capsLock"), isOn: $settings.capsLock),
            .init(id: "network", title: L10n.string("settings.alerts.network"), isOn: $settings.network),
            .init(id: "bluetooth", title: L10n.string("settings.alerts.bluetooth"), isOn: $settings.bluetooth),
            .init(id: "hud", title: L10n.string("settings.alerts.hud"), isOn: $settings.replacesHUD),
        ], footnoteKey: "settings.alerts.system.note")
    }
}
