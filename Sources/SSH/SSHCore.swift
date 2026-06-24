import Foundation
import CSSH

/// Shared low-level libssh2 helpers used by both the interactive `SSHConnection` and the
/// one-shot `SSHBootstrapper`. Keeping these in one place avoids divergence between the two.
enum SSHCore {
    static let HASH_SHA256: Int32 = 3   // LIBSSH2_HOSTKEY_HASH_SHA256

    /// Resolve and connect a TCP socket (IPv4/IPv6, IP or name) with a bounded timeout and TCP
    /// keepalive enabled (so a silently-dropped link is detected in ~30s instead of hanging
    /// forever). Caller owns the fd. Throws a specific `SSHError` based on errno.
    static func connectSocket(host: String, port: UInt16, timeoutMs: Int32 = 10000) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, res != nil else {
            throw SSHError.resolve(host)
        }
        defer { freeaddrinfo(res) }

        var lastErrno: Int32 = ETIMEDOUT
        var p = res
        while let cur = p {
            let fd = socket(cur.pointee.ai_family, cur.pointee.ai_socktype, cur.pointee.ai_protocol)
            if fd >= 0 {
                let err = connectWithTimeout(fd, cur.pointee.ai_addr, cur.pointee.ai_addrlen, timeoutMs)
                if err == 0 { enableKeepalive(fd); return fd }
                lastErrno = err
                close(fd)
            } else {
                lastErrno = errno
            }
            p = cur.pointee.ai_next
        }
        let dest = "\(host):\(port)"
        switch lastErrno {
        case ETIMEDOUT: throw SSHError.timedOut(dest)
        case ECONNREFUSED: throw SSHError.refused(dest)
        case EHOSTUNREACH, ENETUNREACH, EHOSTDOWN: throw SSHError.unreachable(dest)
        default: throw SSHError.connect("\(dest) (\(String(cString: strerror(lastErrno))))")
        }
    }

    /// Non-blocking connect bounded by `timeoutMs`. Returns 0 on success or an errno. Restores the
    /// fd to blocking afterward (libssh2's handshake/auth run in blocking mode).
    private static func connectWithTimeout(_ fd: Int32, _ addr: UnsafeMutablePointer<sockaddr>?,
                                           _ len: socklen_t, _ timeoutMs: Int32) -> Int32 {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, flags) }

        if connect(fd, addr, len) == 0 { return 0 }
        if errno != EINPROGRESS { return errno }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let pr = poll(&pfd, 1, timeoutMs)
        if pr == 0 { return ETIMEDOUT }
        if pr < 0 { return errno }
        var soErr: Int32 = 0
        var l = socklen_t(MemoryLayout<Int32>.size)
        if getsockopt(fd, SOL_SOCKET, SO_ERROR, &soErr, &l) < 0 { return errno }
        return soErr   // 0 = connected
    }

    /// Enable TCP keepalive so the OS probes an idle connection and surfaces a dead peer as a
    /// read/write error (~30s), which the engine loop turns into a `.disconnected` + auto-reconnect.
    private static func enableKeepalive(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, socklen_t(MemoryLayout<Int32>.size))
        var idle: Int32 = 15   // seconds idle before first probe (Darwin TCP_KEEPALIVE)
        setsockopt(fd, IPPROTO_TCP, TCP_KEEPALIVE, &idle, socklen_t(MemoryLayout<Int32>.size))
        var intvl: Int32 = 5
        setsockopt(fd, IPPROTO_TCP, TCP_KEEPINTVL, &intvl, socklen_t(MemoryLayout<Int32>.size))
        var cnt: Int32 = 3
        setsockopt(fd, IPPROTO_TCP, TCP_KEEPCNT, &cnt, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Read the server host key as a `HostKey` (type + SHA-256), for TOFU verification.
    static func readHostKey(_ session: OpaquePointer) -> HostKey? {
        var len = 0
        var type: Int32 = 0
        _ = libssh2_session_hostkey(session, &len, &type)
        guard let hashPtr = libssh2_hostkey_hash(session, HASH_SHA256) else { return nil }
        return HostKey(type: hostKeyTypeName(type), sha256: Data(bytes: hashPtr, count: 32))
    }

    static func hostKeyTypeName(_ t: Int32) -> String {
        switch t {
        case 1: return "ssh-rsa"
        case 2: return "ssh-dss"
        case 3: return "ecdsa-sha2-nistp256"
        case 4: return "ecdsa-sha2-nistp384"
        case 5: return "ecdsa-sha2-nistp521"
        case 6: return "ssh-ed25519"
        default: return "unknown"
        }
    }

    static func lastError(_ session: OpaquePointer?) -> String {
        guard let s = session else { return "no session" }
        var msgPtr: UnsafeMutablePointer<CChar>?
        var msgLen: Int32 = 0
        let code = libssh2_session_last_error(s, &msgPtr, &msgLen, 0)
        let msg = msgPtr.map { String(cString: $0) } ?? ""
        return msg.isEmpty ? "error \(code)" : "\(msg) (\(code))"
    }
}
