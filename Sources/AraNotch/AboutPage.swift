import NotchCore
import NotchShell
import SwiftUI

/// The app's own card: its icon, its name in the display face, and the facts about this
/// copy and this notch.
struct AboutPage: View {
    @Environment(\.araScale) private var ui
    let geometry: NotchGeometry?
    /// Shows the first-run guide again.
    var onShowGuide: (() -> Void)?
    /// The app's updater: the page offers to look for a newer version, or to install the
    /// one already found.
    @ObservedObject var updater: AppUpdater
    /// Called before the updater's own window is asked for, to get the notch out of its way.
    var onCheckForUpdates: (() -> Void)?

    init(
        geometry: NotchGeometry?, updater: AppUpdater, onShowGuide: (() -> Void)? = nil,
        onCheckForUpdates: (() -> Void)? = nil
    ) {
        self.geometry = geometry
        self.updater = updater
        self.onShowGuide = onShowGuide
        self.onCheckForUpdates = onCheckForUpdates
    }

    var body: some View {
        HStack(spacing: 20 * ui) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84 * ui, height: 84 * ui)
            VStack(alignment: .leading, spacing: 7 * ui) {
                Text("AraNotch")
                    .font(AraType.display(24 * ui))
                VStack(alignment: .leading, spacing: 5 * ui) {
                    row("about.version", value: version)
                    if let geometry {
                        row("about.notch", value: L10n.string(geometry.hasPhysicalNotch ? "about.notch.physical" : "about.notch.virtual"))
                        row("about.size", value: sizeText(geometry.closedRect.size))
                    }
                }
                HStack(spacing: 6 * ui) {
                    if let onShowGuide {
                        AraPillButton(L10n.string("about.guide"), icon: .about, action: onShowGuide)
                    }
                    if updater.isAvailable {
                        // A newer version found by a check of its own waits here to be installed.
                        AraPillButton(
                            updater.waitingVersion.map { String(format: L10n.string("update.install"), $0) }
                                ?? L10n.string("update.check"),
                            icon: .reset, isProminent: updater.waitingVersion != nil
                        ) {
                            onCheckForUpdates?()
                            updater.checkForUpdates()
                        }
                    }
                }
                .padding(.top, 2 * ui)
            }
        }
        .padding(.horizontal, 28 * ui)
        .frame(maxHeight: .infinity)
        .araCard(radius: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ labelKey: String, value: String) -> some View {
        AraFactRow(L10n.string(labelKey), value)
            .monospacedDigit()
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }

    private func sizeText(_ size: CGSize) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))
        return "\(Double(size.width).formatted(format)) × \(Double(size.height).formatted(format))"
    }
}
