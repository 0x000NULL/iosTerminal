import Foundation

/// Trust-on-first-use store of server host keys, keyed by "host:port".
/// Backed by a JSON file in the app container. (A future hardened version can move the
/// material into the Keychain; the verification policy is the same.)
final class KnownHostsStore {
    static let shared = KnownHostsStore()

    private struct Entry: Codable { var type: String; var sha256: Data }
    private var entries: [String: Entry]
    private let url: URL
    private let queue = DispatchQueue(label: "KnownHostsStore")

    init(filename: String = "known_hosts.json") {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                in: .userDomainMask, appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        url = dir.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    private func key(_ host: String, _ port: UInt16) -> String { "\(host):\(port)" }

    func status(host: String, port: UInt16, presented: HostKey) -> HostKeyStatus {
        queue.sync {
            guard let stored = entries[key(host, port)] else { return .unknown }
            let storedKey = HostKey(type: stored.type, sha256: stored.sha256)
            return storedKey == presented ? .match : .changed(storedKey)
        }
    }

    func trust(host: String, port: UInt16, key hk: HostKey) {
        queue.sync {
            entries[key(host, port)] = Entry(type: hk.type, sha256: hk.sha256)
            persist()
        }
    }

    func forget(host: String, port: UInt16) {
        queue.sync { entries[key(host, port)] = nil; persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            // Encrypt at rest + tie to device unlock — the TOFU pins are the MITM defense.
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
