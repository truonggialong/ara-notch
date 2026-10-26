import Foundation
import Network

/// Reports whether the Mac has a usable network connection.
@MainActor
final class NetworkMonitor {
    var onChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.onChange?(isOnline) }
        }
        monitor.start(queue: DispatchQueue(label: "com.aranotch.network-monitor"))
    }
}
