import Foundation

/// Throwaway connection details for the SSH **integration** test (`SSHIntegrationTests`).
///
/// The committed value is `nil`, so the integration test SKIPS in normal runs. A local
/// verification run overwrites this file with real values (a disposable local sshd), runs
/// the test, then restores this stub. No real credentials are ever committed.
enum SSHTestConfig {
    struct Config {
        let host: String
        let port: UInt16
        let user: String
        let ed25519KeyB64: String
        let rsaKeyB64: String
    }
    static let current: Config? = nil
}
