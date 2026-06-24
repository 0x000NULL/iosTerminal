import Foundation

/// A transport that does nothing but report a failure — used when a profile can't be turned
/// into a real transport (e.g. its Keychain secret is missing).
final class FailedTransport: Transport {
    private let message: String
    var state: TransportState { .failed(message) }
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?

    init(_ message: String) { self.message = message }

    func connect() { onStateChange?(.failed(message)) }
    func send(_ bytes: [UInt8]) {}
    func resize(cols: Int, rows: Int) {}
    func disconnect() {}
}
