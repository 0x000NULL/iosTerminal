import Foundation

/// High-level connection state surfaced to the UI.
enum TransportState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected(String?)
    case failed(String)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting…"
        case .disconnected(let r): return "Disconnected" + (r.map { " — \($0)" } ?? "")
        case .failed(let m): return "Failed — \(m)"
        }
    }
}

/// A byte-stream transport that backs a terminal session (SSH, Mosh, or a local demo).
///
/// Threading contract (enforced by every implementation):
///  - `onReceive` may be invoked on a **background** thread. SwiftTerm's `feed(byteArray:)`
///    is documented background-safe, so the receive loop can call it directly.
///  - `send(_:)` and `resize(cols:rows:)` are called from the **main** thread (UIKit key/IME
///    origin). They MUST NOT block: implementations enqueue onto their own serial work queue
///    and return immediately. All transport/client state is guarded by that single queue.
///  - `onStateChange` is always delivered on the **main** queue.
protocol Transport: AnyObject {
    var state: TransportState { get }

    /// Inbound bytes from the host. Set before `connect()`. Invoked off the main thread.
    var onReceive: (([UInt8]) -> Void)? { get set }

    /// State transitions, delivered on the main queue.
    var onStateChange: ((TransportState) -> Void)? { get set }

    func connect()
    func send(_ bytes: [UInt8])
    func resize(cols: Int, rows: Int)
    func disconnect()
}
