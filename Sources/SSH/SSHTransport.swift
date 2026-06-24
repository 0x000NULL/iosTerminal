import Foundation

/// Interactive SSH PTY shell transport (libssh2). Bridges an `SSHConnection` to the
/// `Transport` protocol so a `TerminalView` can drive a real tmux + coding agents session.
final class SSHTransport: Transport {
    private(set) var state: TransportState = .idle {
        didSet { let s = state; DispatchQueue.main.async { self.onStateChange?(s) } }
    }
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?

    /// Optional UI hook for host-key decisions. Called on the SSH engine thread, so it must
    /// return synchronously (block on a semaphore if you present UI). If nil, the default
    /// policy is TOFU: trust an unknown host, REJECT a changed key.
    var hostKeyPrompt: ((HostKey, HostKeyStatus) -> Bool)?

    private let config: SSHConfig
    private let knownHosts: KnownHostsStore
    private var connection: SSHConnection?

    init(config: SSHConfig, knownHosts: KnownHostsStore = .shared) {
        self.config = config
        self.knownHosts = knownHosts
    }

    func connect() {
        let conn = SSHConnection(
            config: config,
            onData: { [weak self] bytes in self?.onReceive?(bytes) },
            onState: { [weak self] s in self?.state = s },
            verifyHostKey: { [weak self] presented in self?.decideHostKey(presented) ?? false }
        )
        connection = conn
        conn.start()
    }

    func send(_ bytes: [UInt8]) { connection?.write(bytes) }
    func resize(cols: Int, rows: Int) { connection?.resize(cols: cols, rows: rows) }
    func disconnect() { connection?.stop() }

    private func decideHostKey(_ presented: HostKey) -> Bool {
        HostKeyPolicy.decide(host: config.host, port: config.port, presented: presented,
                             knownHosts: knownHosts, prompt: hostKeyPrompt)
    }
}
