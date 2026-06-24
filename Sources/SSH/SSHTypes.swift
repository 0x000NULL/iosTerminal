import Foundation

/// How to authenticate to the host.
enum SSHAuth {
    case password(String)
    /// OpenSSH/PEM private key bytes (ed25519 or RSA) + optional passphrase.
    case privateKey(pem: Data, passphrase: String?)
    /// No credential — the server accepts the SSH `none` method. This is how **Tailscale's
    /// built-in SSH** works (your tailnet identity authenticates you).
    case none
    // TODO: Secure Enclave P-256 needs a libssh2 sign-callback path; tracked for #5.
}

/// Everything needed to open one SSH session.
struct SSHConfig {
    var host: String                // tailnet 100.x IP (preferred) or MagicDNS name
    var port: UInt16 = 22
    var username: String
    var auth: SSHAuth
    var termType: String = "xterm-256color"
    var cols: Int = 80
    var rows: Int = 24
    /// Optional command written to the shell right after it starts (e.g. `tmux new -A -s main`).
    var initialCommand: String?
}

/// A server host key, for TOFU verification.
struct HostKey: Equatable {
    var type: String        // e.g. "ssh-ed25519"
    var sha256: Data        // 32-byte SHA-256 of the key blob

    /// OpenSSH-style fingerprint: `SHA256:<base64 no padding>`.
    var fingerprint: String {
        let b64 = sha256.base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(b64)"
    }
}

/// Result of checking a presented host key against what we've stored.
enum HostKeyStatus {
    case unknown        // never seen this host → trust on first use
    case match          // matches what we stored
    case changed(HostKey) // DIFFERENT from what we stored → possible MITM
}

enum SSHError: Error, CustomStringConvertible {
    case resolve(String)
    case connect(String)
    case timedOut(String)
    case unreachable(String)
    case refused(String)
    case handshake(String)
    case hostKeyRejected(String)
    case auth(String)
    case channel(String)
    case disconnected(String)

    var description: String {
        switch self {
        case .resolve(let s): return "Can't resolve \(s) — is Tailscale up?"
        case .connect(let s): return "Connection failed: \(s)"
        case .timedOut(let s): return "Timed out connecting to \(s) — is Tailscale up / the host awake?"
        case .unreachable(let s): return "Host unreachable (\(s)) — is Tailscale up?"
        case .refused(let s): return "Connection refused by \(s) — is sshd running on that port?"
        case .handshake(let s): return "SSH handshake failed: \(s)"
        case .hostKeyRejected(let s): return "Host key rejected: \(s)"
        case .auth(let s): return "Authentication failed: \(s)"
        case .channel(let s): return "Channel error: \(s)"
        case .disconnected(let s): return "Disconnected: \(s)"
        }
    }
}
