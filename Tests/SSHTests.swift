import XCTest
@testable import iosTerminal

final class SSHTests: XCTestCase {

    func testHostKeyFingerprintFormat() {
        let k = HostKey(type: "ssh-ed25519", sha256: Data(repeating: 0, count: 32))
        XCTAssertTrue(k.fingerprint.hasPrefix("SHA256:"))
        XCTAssertFalse(k.fingerprint.contains("="), "OpenSSH fingerprints have no base64 padding")
    }

    func testKnownHostsTOFUFlow() {
        let store = KnownHostsStore(filename: "test-known-hosts-\(UUID().uuidString).json")
        let host = "100.64.0.1"; let port: UInt16 = 22
        let k1 = HostKey(type: "ssh-ed25519", sha256: Data(repeating: 1, count: 32))
        let k2 = HostKey(type: "ssh-ed25519", sha256: Data(repeating: 2, count: 32))

        // First contact → unknown.
        guard case .unknown = store.status(host: host, port: port, presented: k1) else {
            return XCTFail("first contact should be unknown")
        }
        store.trust(host: host, port: port, key: k1)

        // Same key → match.
        guard case .match = store.status(host: host, port: port, presented: k1) else {
            return XCTFail("trusted key should match")
        }

        // Different key → changed (carries the previously-stored key).
        guard case .changed(let stored) = store.status(host: host, port: port, presented: k2) else {
            return XCTFail("a different key must be reported as changed")
        }
        XCTAssertEqual(stored, k1)

        store.forget(host: host, port: port)
        guard case .unknown = store.status(host: host, port: port, presented: k1) else {
            return XCTFail("forgotten host should be unknown again")
        }
    }
}
