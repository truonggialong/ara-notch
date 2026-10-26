import CalendarCore
import NotchShell
import SwiftUI

/// The calendar's line in Settings › Notices: the meeting about to start.
struct CalendarSettingsSection: View {
    @ObservedObject var settings: CalendarSettings

    var body: some View {
        // Off, or how long before: one choice instead of a switch and a choice under it.
        Picker(selection: Binding(
            get: { settings.meetingAlerts ? settings.leadMinutes : 0 },
            set: { minutes in
                settings.meetingAlerts = minutes > 0
                if minutes > 0 { settings.leadMinutes = minutes }
            }
        )) {
            Text(L10n.string("settings.off")).tag(0)
            ForEach(CalendarSettingsStore.leadChoices, id: \.self) { minutes in
                Text(String(format: L10n.string("settings.calendar.lead.minutes"), minutes)).tag(minutes)
            }
        } label: {
            Text(L10n.string("settings.calendar.alerts"))
            AraSettingsNote(L10n.string("settings.calendar.note"))
        }
    }
}

/// The calendar page's line in Settings › Notch pages: the lunar date.
struct CalendarPageSettings: View {
    @ObservedObject var settings: CalendarSettings

    var body: some View {
        Toggle(isOn: $settings.showsLunarDate) {
            Text(L10n.string("settings.calendar.lunar"))
            AraSettingsNote(L10n.string("settings.calendar.lunar.note"))
        }
    }
}
