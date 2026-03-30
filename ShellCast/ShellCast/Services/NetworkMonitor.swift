import Foundation
import Network

/// Monitors network path changes (WiFi ↔ cellular) and notifies observers.
/// Used to proactively trigger SSH reconnection when the network interface changes.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true
    private(set) var isCellular = false
    private(set) var isWiFi = false
    private(set) var interfaceType: NWInterface.InterfaceType?

    /// Fires when network path changes (e.g., WiFi → cellular handoff).
    /// The closure receives `true` if network is now satisfied, `false` otherwise.
    var onNetworkChange: ((Bool) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shellcast.networkmonitor", qos: .utility)
    private var previousInterfaceType: NWInterface.InterfaceType?

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            let wasConnected = self.isConnected
            let oldInterface = self.previousInterfaceType

            let newConnected = path.status == .satisfied
            let newCellular = path.usesInterfaceType(.cellular)
            let newWiFi = path.usesInterfaceType(.wifi)

            let newInterfaceType: NWInterface.InterfaceType? = if newWiFi {
                .wifi
            } else if newCellular {
                .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                .wiredEthernet
            } else {
                nil
            }

            DispatchQueue.main.async {
                self.isConnected = newConnected
                self.isCellular = newCellular
                self.isWiFi = newWiFi
                self.interfaceType = newInterfaceType
                self.previousInterfaceType = newInterfaceType

                // Notify on any meaningful change:
                // 1. Connection lost or restored
                // 2. Interface type changed (WiFi ↔ cellular handoff)
                let interfaceChanged = oldInterface != nil && newInterfaceType != nil && oldInterface != newInterfaceType
                let connectionChanged = wasConnected != newConnected

                if connectionChanged || interfaceChanged {
                    let reason = interfaceChanged ? "interface changed (\(oldInterface.debugName) → \(newInterfaceType.debugName))" : "connection \(newConnected ? "restored" : "lost")"
                    print("[NET] Network change: \(reason), satisfied=\(newConnected)")
                    self.onNetworkChange?(newConnected)
                }
            }
        }
        monitor.start(queue: queue)
        print("[NET] NetworkMonitor started")
    }

    func stop() {
        monitor.cancel()
        print("[NET] NetworkMonitor stopped")
    }
}

// MARK: - Debug helpers

private extension Optional where Wrapped == NWInterface.InterfaceType {
    var debugName: String {
        guard let self else { return "none" }
        switch self {
        case .wifi: return "WiFi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }
}
