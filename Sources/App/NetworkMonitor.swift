import Foundation
import Network

/// Observes connectivity + interface changes (Wi-Fi↔cellular). Used to trigger a reconnect
/// when the path changes while the app is foregrounded.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline = true
    @Published private(set) var isExpensive = false   // cellular / hotspot

    /// Fired when the network path meaningfully changes (interface or reachability).
    var onPathChange: (() -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    private var lastInterface: NWInterface.InterfaceType?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let expensive = path.isExpensive
            let iface = path.availableInterfaces.first?.type
            Task { @MainActor in
                guard let self else { return }
                let changed = (iface != self.lastInterface) || (online != self.isOnline)
                self.isOnline = online
                self.isExpensive = expensive
                self.lastInterface = iface
                if changed { self.onPathChange?() }
            }
        }
        monitor.start(queue: queue)
    }
}
