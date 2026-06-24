import Foundation

/// Shared TOFU decision used by every transport: trust an unknown host (pin it), reject a
/// changed key unless a prompt explicitly re-pins it.
enum HostKeyPolicy {
    static func decide(host: String,
                       port: UInt16,
                       presented: HostKey,
                       knownHosts: KnownHostsStore,
                       prompt: ((HostKey, HostKeyStatus) -> Bool)?) -> Bool {
        switch knownHosts.status(host: host, port: port, presented: presented) {
        case .match:
            return true
        case .unknown:
            if let prompt, !prompt(presented, .unknown) { return false }
            knownHosts.trust(host: host, port: port, key: presented)
            return true
        case .changed(let stored):
            if let prompt, prompt(presented, .changed(stored)) {
                knownHosts.trust(host: host, port: port, key: presented)
                return true
            }
            return false
        }
    }
}
