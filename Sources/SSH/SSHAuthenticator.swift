import Foundation
import CSSH

/// Shared user-authentication step, used by both the interactive and bootstrap paths.
enum SSHAuthenticator {
    static func authenticate(_ session: OpaquePointer, config: SSHConfig) throws {
        let user = config.username
        let ulen = UInt32(user.utf8.count)

        // Probe the SSH "none" method first. `libssh2_userauth_list` sends a "none" auth
        // request; if the server accepts it (Tailscale built-in SSH, or any pre-authenticated
        // setup), we're done. For a normal server this just returns the allowed-method list.
        _ = libssh2_userauth_list(session, user, ulen)
        if libssh2_userauth_authenticated(session) != 0 { return }

        var rc: Int32
        switch config.auth {
        case .none:
            throw SSHError.auth("Server did not accept passwordless (none) auth. If this is Tailscale SSH, it likely requires browser/check authentication (not supported yet) — or use a real sshd with a key.")
        case .password(let pw):
            rc = libssh2_userauth_password_ex(session, user, ulen, pw, UInt32(pw.utf8.count), nil)
        case .privateKey(let pem, let passphrase):
            rc = pem.withUnsafeBytes { raw -> Int32 in
                let priv = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
                if let pass = passphrase {
                    return libssh2_userauth_publickey_frommemory(
                        session, user, user.utf8.count, nil, 0, priv, pem.count, pass)
                } else {
                    return libssh2_userauth_publickey_frommemory(
                        session, user, user.utf8.count, nil, 0, priv, pem.count, nil)
                }
            }
        }
        guard rc == 0 else { throw SSHError.auth(SSHCore.lastError(session)) }
    }
}
