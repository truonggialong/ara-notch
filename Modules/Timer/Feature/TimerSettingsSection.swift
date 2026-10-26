import NotchShell
import SwiftUI

/// The timer's line in Settings › Notices.
struct TimerSettingsSection: View {
    @ObservedObject var settings: TimerSettings

    var body: some View {
        Toggle(L10n.string("settings.timer.sound"), isOn: $settings.soundEnabled)
    }
}
