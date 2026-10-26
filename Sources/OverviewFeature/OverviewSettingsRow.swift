import NotchShell
import OverviewCore
import SwiftUI

/// Settings › Notch pages: the overview's tiles are arranged on the notch itself; here they
/// can only be put back.
struct OverviewSettingsRow: View {
    @ObservedObject var settings: OverviewSettings

    var body: some View {
        LabeledContent {
            Button(L10n.string("settings.overview.reset")) {
                settings.arrangement = OverviewGrid.defaultArrangement
            }
            .disabled(settings.arrangement == OverviewGrid.defaultArrangement)
        } label: {
            Text(L10n.string("settings.overview"))
            AraSettingsNote(L10n.string("settings.overview.hint"))
        }
    }
}
