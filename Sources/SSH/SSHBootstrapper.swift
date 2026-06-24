import Foundation
import CSSH

/// One-shot, blocking SSH command runner used for the mosh bootstrap (`mosh-server new ...`).
/// Connects, verifies the host key (same TOFU policy), authenticates, runs the command via an
/// exec channel, and returns its full stdout.
enum SSHBootstrapper {
    static func run(config: SSHConfig, command: String, verifyHostKey: (HostKey) -> Bool) throws -> String {
        SSHLibrary.initialize()
        let sock = try SSHCore.connectSocket(host: config.host, port: config.port)
        defer { close(sock) }

        guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
            throw SSHError.handshake("session init")
        }
        defer {
            libssh2_session_disconnect_ex(session, 11, "bye", "")
            libssh2_session_free(session)
        }
        libssh2_session_set_blocking(session, 1)
        guard libssh2_session_handshake(session, sock) == 0 else {
            throw SSHError.handshake(SSHCore.lastError(session))
        }
        guard let hk = SSHCore.readHostKey(session) else { throw SSHError.handshake("no host key") }
        guard verifyHostKey(hk) else { throw SSHError.hostKeyRejected(hk.fingerprint) }
        try SSHAuthenticator.authenticate(session, config: config)

        guard let ch = libssh2_channel_open_ex(session, "session", 7, 2 * 1024 * 1024, 32768, nil, 0) else {
            throw SSHError.channel(SSHCore.lastError(session))
        }
        defer { libssh2_channel_close(ch); libssh2_channel_free(ch) }
        guard libssh2_channel_process_startup(ch, "exec", 4, command, UInt32(command.utf8.count)) == 0 else {
            throw SSHError.channel("exec: \(SSHCore.lastError(session))")
        }

        var out = Data()
        var buf = [CChar](repeating: 0, count: 4096)
        while true {
            let n = libssh2_channel_read_ex(ch, 0, &buf, buf.count)
            if n > 0 { out.append(contentsOf: buf[0..<n].map { UInt8(bitPattern: $0) }) }
            else { break }   // blocking read: 0 = EOF, <0 = error
        }
        return String(decoding: out, as: UTF8.self)
    }
}
