import Foundation
import Network

/// Reports connectivity changes on the main actor.
@MainActor
final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private(set) var isConnected = true

    var onChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in self?.update(connected) }
        }
        monitor.start(queue: DispatchQueue(label: "DeepSeekNative.NetworkMonitor", qos: .utility))
    }

    private func update(_ connected: Bool) {
        guard connected != isConnected else { return }
        isConnected = connected
        onChange?(connected)
    }
}
