import Foundation

/// Orchestrates a mosh session end-to-end as a single `Transport`:
/// 1. SSH-exec `mosh-server new … -- tmux …` and parse `MOSH CONNECT <port> <key>`,
/// 2. start `MoshTransport` over UDP to that port using `MOSH_KEY`,
/// 3. forward its bytes/state.
///
/// The mosh engine itself (`mosh_main`) is gated behind `MOSH_ENABLED`; until the framework
/// is added, step 2's `connect()` reports a clear "Mosh not enabled" state — but the SSH
/// bootstrap + parse (steps 1) run and are independently testable.
final class MoshSessionTransport: Transport {
    private(set) var state: TransportState = .idle {
        didSet { let s = state; DispatchQueue.main.async { self.onStateChange?(s) } }
    }
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?
    var hostKeyPrompt: ((HostKey, HostKeyStatus) -> Bool)?

    private let sshConfig: SSHConfig
    private let moshExec: String?
    private let predictionMode: String
    private let locale: String
    private let knownHosts: KnownHostsStore
    private var inner: MoshTransport?

    init(sshConfig: SSHConfig, moshExec: String?, predictionMode: String = "adaptive",
         locale: String = "en_US.UTF-8", knownHosts: KnownHostsStore = .shared) {
        self.sshConfig = sshConfig
        self.moshExec = moshExec
        self.predictionMode = predictionMode
        self.locale = locale
        self.knownHosts = knownHosts
    }

    func connect() {
        state = .connecting
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let cmd = MoshBootstrap.serverCommand(locale: self.locale, exec: self.moshExec)
                let output = try SSHBootstrapper.run(
                    config: self.sshConfig, command: cmd,
                    verifyHostKey: { presented in
                        HostKeyPolicy.decide(host: self.sshConfig.host, port: self.sshConfig.port,
                                             presented: presented, knownHosts: self.knownHosts,
                                             prompt: self.hostKeyPrompt)
                    })
                guard let info = MoshBootstrap.parseConnect(output) else {
                    self.state = .failed("Could not parse MOSH CONNECT — check the server's locale and that rc files print nothing before the banner.")
                    return
                }
                let mosh = MoshTransport(ip: self.sshConfig.host, port: info.port, key: info.key,
                                         predictionMode: self.predictionMode)
                mosh.onReceive = { [weak self] bytes in self?.onReceive?(bytes) }
                mosh.onStateChange = { [weak self] s in self?.state = s }
                self.inner = mosh
                mosh.connect()
            } catch let e as SSHError {
                self.state = .failed(e.description)
            } catch {
                self.state = .failed("\(error)")
            }
        }
    }

    func send(_ bytes: [UInt8]) { inner?.send(bytes) }
    func resize(cols: Int, rows: Int) { inner?.resize(cols: cols, rows: rows) }
    func disconnect() { inner?.disconnect() }
}
