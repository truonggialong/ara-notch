import Combine
import ServiceManagement

/// Whether the app opens when the user logs in. Changing it adds the app to, or removes it
/// from, the Login Items in System Settings.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled
    /// Why the last change did not take, in the system's words.
    @Published private(set) var problem: String?

    /// Where the app was when it was last registered; a copy moved elsewhere (out of a build
    /// folder into Applications, say) registers itself again, so login opens this copy.
    private static let registeredPathKey = "loginItem.registeredPath"

    init() {
        let path = Bundle.main.bundlePath
        let registered = UserDefaults.standard.string(forKey: Self.registeredPathKey)
        if isEnabled, registered != path {
            try? SMAppService.mainApp.unregister()
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(path, forKey: Self.registeredPathKey)
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(Bundle.main.bundlePath, forKey: Self.registeredPathKey)
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }
}
