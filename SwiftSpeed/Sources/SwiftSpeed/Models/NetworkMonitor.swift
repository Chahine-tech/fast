import Foundation
import Network

/// Tracks which network interface is active and whether it's connected.
/// Deliberately does not track live throughput: a getifaddrs-based bytes/s
/// reading is *current traffic on the machine*, not the line's capacity, and
/// showing it next to the Speed Test result made the two easy to confuse.
@MainActor
final class NetworkMonitor: ObservableObject {
    @Published var activeInterface: String = "Offline"
    @Published var isConnected: Bool = true

    private let pathMonitor = NWPathMonitor()

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                if path.usesInterfaceType(.wifi) {
                    self?.activeInterface = "Wi-Fi"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.activeInterface = "Ethernet"
                } else if path.status == .satisfied {
                    self?.activeInterface = "Other"
                } else {
                    self?.activeInterface = "Offline"
                }
            }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    func stop() {
        pathMonitor.cancel()
    }
}
