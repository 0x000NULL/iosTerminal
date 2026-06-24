import XCTest
@testable import iosTerminal

/// End-to-end SSH test driving `SSHTransport` against a real OpenSSH server. Skips unless
/// `SSHTestConfig.current` is populated (a local disposable sshd). Verifies: TCP connect →
/// handshake → host-key TOFU → public-key auth → PTY shell → bidirectional read/write.
final class SSHIntegrationTests: XCTestCase {

    func testSSHShellEd25519() throws {
        let c = try config()
        try runShell(keyB64: c.ed25519KeyB64, host: c.host, port: c.port, user: c.user)
    }

    func testSSHShellRSA() throws {
        let c = try config()
        try runShell(keyB64: c.rsaKeyB64, host: c.host, port: c.port, user: c.user)
    }

    private func config() throws -> SSHTestConfig.Config {
        guard let c = SSHTestConfig.current else {
            throw XCTSkip("No SSH test config — integration test skipped (normal in CI/unit runs).")
        }
        return c
    }

    private func runShell(keyB64: String, host: String, port: UInt16, user: String) throws {
        let pem = try XCTUnwrap(Data(base64Encoded: keyB64), "bad base64 key")
        let cfg = SSHConfig(host: host, port: port, username: user,
                            auth: .privateKey(pem: pem, passphrase: nil))
        let transport = SSHTransport(config: cfg)

        let connected = expectation(description: "reached .connected (handshake+auth+pty)")
        let echoed = expectation(description: "marker round-tripped through the channel")
        echoed.assertForOverFulfill = false

        let marker = "IOSTERM_RT_\(UInt32.random(in: 100_000...999_999))"
        let buf = NSMutableData()
        let lock = NSLock()

        transport.onStateChange = { state in
            switch state {
            case .connected: connected.fulfill()
            case .failed(let m): XCTFail("SSH failed: \(m)")
            default: break
            }
        }
        transport.onReceive = { bytes in
            lock.lock()
            buf.append(Data(bytes))
            let s = String(decoding: buf as Data, as: UTF8.self)
            lock.unlock()
            if s.contains(marker) { echoed.fulfill() }
        }

        transport.connect()
        wait(for: [connected], timeout: 20)
        transport.send(Array("echo \(marker)\n".utf8))
        wait(for: [echoed], timeout: 20)
        transport.disconnect()
    }
}
