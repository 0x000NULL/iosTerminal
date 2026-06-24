import XCTest
@testable import iosTerminal

/// The MITM-defense decision used by every transport: trust unknown (pin), reject changed unless
/// the prompt explicitly re-pins. Branchy and security-critical → exhaustively covered here.
final class HostKeyPolicyTests: XCTestCase {
    private func store() -> KnownHostsStore { KnownHostsStore(filename: "hkp-\(UUID().uuidString).json") }
    private let host = "100.64.0.9"
    private let port: UInt16 = 22
    private let k1 = HostKey(type: "ssh-ed25519", sha256: Data(repeating: 1, count: 32))
    private let k2 = HostKey(type: "ssh-ed25519", sha256: Data(repeating: 2, count: 32))

    func testUnknownNoPromptAutoTrustsAndPins() {
        let s = store()
        XCTAssertTrue(HostKeyPolicy.decide(host: host, port: port, presented: k1, knownHosts: s, prompt: nil))
        guard case .match = s.status(host: host, port: port, presented: k1) else { return XCTFail("should pin") }
    }

    func testUnknownPromptDenyDoesNotPin() {
        let s = store()
        XCTAssertFalse(HostKeyPolicy.decide(host: host, port: port, presented: k1, knownHosts: s, prompt: { _, _ in false }))
        guard case .unknown = s.status(host: host, port: port, presented: k1) else { return XCTFail("must not pin on deny") }
    }

    func testChangedNoPromptRejectsAndKeepsOldKey() {
        let s = store()
        s.trust(host: host, port: port, key: k1)
        XCTAssertFalse(HostKeyPolicy.decide(host: host, port: port, presented: k2, knownHosts: s, prompt: nil))
        guard case .changed(let stored) = s.status(host: host, port: port, presented: k2) else { return XCTFail() }
        XCTAssertEqual(stored, k1, "old key must remain pinned after a silent reject")
    }

    func testChangedPromptApproveRepins() {
        let s = store()
        s.trust(host: host, port: port, key: k1)
        XCTAssertTrue(HostKeyPolicy.decide(host: host, port: port, presented: k2, knownHosts: s, prompt: { _, _ in true }))
        guard case .match = s.status(host: host, port: port, presented: k2) else { return XCTFail("should re-pin to the new key") }
    }

    func testChangedPromptDenyKeepsOldKey() {
        let s = store()
        s.trust(host: host, port: port, key: k1)
        XCTAssertFalse(HostKeyPolicy.decide(host: host, port: port, presented: k2, knownHosts: s, prompt: { _, _ in false }))
        guard case .changed(let stored) = s.status(host: host, port: port, presented: k2) else { return XCTFail() }
        XCTAssertEqual(stored, k1)
    }
}
