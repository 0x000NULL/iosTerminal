import Foundation
import CSSH

/// Owns one libssh2 session on a dedicated thread. All libssh2 calls happen on that thread
/// (libssh2 sessions are not thread-safe); `write`/`resize` enqueue work that the engine loop
/// drains. Setup (handshake/auth/channel) runs blocking; the I/O loop runs non-blocking + poll.
final class SSHConnection {
    // libssh2 constants (the function-like macros don't import into Swift).
    private let EAGAIN: Int = -37                       // LIBSSH2_ERROR_EAGAIN
    private let WINDOW_DEFAULT: UInt32 = 2 * 1024 * 1024 // LIBSSH2_CHANNEL_WINDOW_DEFAULT
    private let PACKET_DEFAULT: UInt32 = 32768           // LIBSSH2_CHANNEL_PACKET_DEFAULT

    private let config: SSHConfig
    private let onData: ([UInt8]) -> Void
    private let onState: (TransportState) -> Void
    /// Return true to accept the presented host key, false to abort.
    private let verifyHostKey: (HostKey) -> Bool

    private var sock: Int32 = -1
    private var session: OpaquePointer?
    private var channel: OpaquePointer?
    private var thread: Thread?

    private let lock = NSLock()
    private var outBuffer: [UInt8] = []
    private var pendingResize: (Int, Int)?
    private var stopFlag = false

    init(config: SSHConfig,
         onData: @escaping ([UInt8]) -> Void,
         onState: @escaping (TransportState) -> Void,
         verifyHostKey: @escaping (HostKey) -> Bool) {
        self.config = config
        self.onData = onData
        self.onState = onState
        self.verifyHostKey = verifyHostKey
    }

    func start() {
        let t = Thread { [weak self] in self?.run() }
        t.name = "SSHConnection"
        t.stackSize = 1 << 20
        thread = t
        t.start()
    }

    func write(_ bytes: [UInt8]) {
        lock.lock(); outBuffer.append(contentsOf: bytes); lock.unlock()
    }

    func resize(cols: Int, rows: Int) {
        lock.lock(); pendingResize = (cols, rows); lock.unlock()
    }

    func stop() {
        lock.lock(); stopFlag = true; lock.unlock()
    }

    // MARK: - Engine thread

    private func run() {
        report(.connecting)
        do {
            SSHLibrary.initialize()
            sock = try SSHCore.connectSocket(host: config.host, port: config.port)
            try handshakeAndAuth()
            try openShell()
            report(.connected)
            ioLoop()
            report(.disconnected("session ended"))
        } catch let e as SSHError {
            report(.failed(e.description))
        } catch {
            report(.failed("\(error)"))
        }
        cleanup()
    }

    private func handshakeAndAuth() throws {
        guard let s = libssh2_session_init_ex(nil, nil, nil, nil) else {
            throw SSHError.handshake("session init")
        }
        session = s
        libssh2_session_set_blocking(s, 1)
        libssh2_session_set_timeout(s, 15000)   // 15s cap so handshake/auth can't hang forever
        guard libssh2_session_handshake(s, sock) == 0 else {
            throw SSHError.handshake(SSHCore.lastError(s))
        }
        guard let presented = SSHCore.readHostKey(s) else { throw SSHError.handshake("no host key") }
        guard verifyHostKey(presented) else { throw SSHError.hostKeyRejected(presented.fingerprint) }
        try SSHAuthenticator.authenticate(s, config: config)
        // App-level keepalive (server echo replies) on top of socket TCP keepalive.
        libssh2_keepalive_config(s, 1, 30)
    }

    private func openShell() throws {
        guard let s = session else { throw SSHError.channel("no session") }
        guard let ch = libssh2_channel_open_ex(s, "session", 7, WINDOW_DEFAULT, PACKET_DEFAULT, nil, 0) else {
            throw SSHError.channel(SSHCore.lastError(s))
        }
        channel = ch
        let term = config.termType
        let prc = libssh2_channel_request_pty_ex(
            ch, term, UInt32(term.utf8.count), nil, 0,
            Int32(config.cols), Int32(config.rows), 0, 0)
        guard prc == 0 else { throw SSHError.channel("pty: \(SSHCore.lastError(s))") }
        guard libssh2_channel_process_startup(ch, "shell", 5, nil, 0) == 0 else {
            throw SSHError.channel("shell: \(SSHCore.lastError(s))")
        }
        libssh2_session_set_blocking(s, 0)   // I/O loop is non-blocking
        if let cmd = config.initialCommand, !cmd.isEmpty {
            write(Array((cmd + "\n").utf8))   // e.g. auto-attach tmux
        }
    }

    private func ioLoop() {
        guard let ch = channel else { return }
        var readBuf = [CChar](repeating: 0, count: 32768)

        while !shouldStop() {
            drainWrites(ch)
            applyResize(ch)

            var didRead = false
            readLoop: while true {
                let n = libssh2_channel_read_ex(ch, 0, &readBuf, readBuf.count)
                if n > 0 {
                    didRead = true
                    onData(readBuf[0..<n].map { UInt8(bitPattern: $0) })
                } else if n == EAGAIN {
                    break readLoop
                } else {
                    // 0 = EOF on stream, <0 = error
                    if n < 0 { lock.lock(); stopFlag = true; lock.unlock() }
                    break readLoop
                }
            }

            if libssh2_channel_eof(ch) != 0 { break }

            // Keepalive: only sends when the 30s interval elapses; a hard failure means the peer
            // is gone (combined with TCP keepalive this turns a silent half-open link into a fast
            // .disconnected → auto-reconnect, instead of a frozen "Connected" session).
            if let s = session {
                var secs: Int32 = 0
                let krc = libssh2_keepalive_send(s, &secs)
                if krc < 0 && Int(krc) != EAGAIN {
                    lock.lock(); stopFlag = true; lock.unlock()
                    break
                }
            }

            if !didRead { waitSocket(timeoutMs: 200) }
        }
    }

    private func drainWrites(_ ch: OpaquePointer) {
        lock.lock(); let data = outBuffer; outBuffer.removeAll(keepingCapacity: true); lock.unlock()
        guard !data.isEmpty else { return }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            var off = 0
            while off < data.count {
                let n = libssh2_channel_write_ex(ch, 0, base + off, data.count - off)
                if n == EAGAIN {
                    lock.lock(); outBuffer.insert(contentsOf: data[off...], at: 0); lock.unlock()
                    return
                } else if n < 0 {
                    lock.lock(); stopFlag = true; lock.unlock(); return
                } else {
                    off += n
                }
            }
        }
    }

    private func applyResize(_ ch: OpaquePointer) {
        lock.lock(); let resize = pendingResize; pendingResize = nil; lock.unlock()
        if let (c, r) = resize {
            _ = libssh2_channel_request_pty_size_ex(ch, Int32(c), Int32(r), 0, 0)
        }
    }

    private func waitSocket(timeoutMs: Int32) {
        var pfd = pollfd(fd: sock, events: Int16(truncatingIfNeeded: POLLIN | POLLOUT), revents: 0)
        _ = poll(&pfd, 1, timeoutMs)
    }

    private func shouldStop() -> Bool {
        lock.lock(); defer { lock.unlock() }; return stopFlag
    }

    private func cleanup() {
        if let ch = channel {
            libssh2_channel_close(ch)
            libssh2_channel_free(ch)
            channel = nil
        }
        if let s = session {
            libssh2_session_disconnect_ex(s, 11 /* SSH_DISCONNECT_BY_APPLICATION */, "bye", "")
            libssh2_session_free(s)
            session = nil
        }
        if sock >= 0 { close(sock); sock = -1 }
    }

    private func report(_ s: TransportState) {
        DispatchQueue.main.async { self.onState(s) }
    }
}
