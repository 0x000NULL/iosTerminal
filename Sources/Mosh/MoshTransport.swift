import Foundation
#if MOSH_ENABLED
import mosh   // module vended by mosh.xcframework (moshiosbridge.h; GPL — personal build only)
#endif

/// Drives Blink's prebuilt mosh `ios-controller` (`mosh_main`) and bridges its stdin/stdout
/// `FILE*`s to SwiftTerm via POSIX pipes. See `docs/MOSH_INTEGRATION.md`.
///
/// The GPL touch points (`import CMosh`, the `mosh_main` call) are gated behind `MOSH_ENABLED`
/// so the default build stays MIT-clean and green; the pipe/winsize/threading mechanics below
/// are pure POSIX and always compiled. Supply `ip`/`port`/`key` from the SSH bootstrap.
final class MoshTransport: Transport {
    private(set) var state: TransportState = .idle {
        didSet { let s = state; DispatchQueue.main.async { self.onStateChange?(s) } }
    }
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?

    private let ip: String
    private let port: String
    private let key: String
    private let predictionMode: String

    /// Latest encoded session state from mosh's `state_callback`, for foreground roam. In-memory only.
    fileprivate var stateBlob: Data?

    // Pipes: app → mosh stdin (inFds), mosh stdout → app (outFds).
    private var inFds: [Int32] = [-1, -1]
    private var outFds: [Int32] = [-1, -1]
    private var fIn: UnsafeMutablePointer<FILE>?
    private var fOut: UnsafeMutablePointer<FILE>?

    /// Stable winsize the controller re-reads on SIGWINCH.
    private let winPtr = UnsafeMutablePointer<winsize>.allocate(capacity: 1)
    private var moshThread: pthread_t?
    private var reader: Thread?
    private let writeQueue = DispatchQueue(label: "MoshTransport.write")

    init(ip: String, port: String, key: String, predictionMode: String = "adaptive",
         cols: Int = 80, rows: Int = 24) {
        self.ip = ip
        self.port = port
        self.key = key
        self.predictionMode = predictionMode
        // Start at the real screen size if it's known (the bootstrap caches the view's last
        // reported size); mosh_main reads winPtr when the engine thread starts, so tmux attaches
        // at the correct width instead of 80x24 → no initial wrap/clip + reflow.
        winPtr.pointee = winsize(ws_row: UInt16(max(1, rows)), ws_col: UInt16(max(1, cols)),
                                 ws_xpixel: 0, ws_ypixel: 0)
    }

    deinit { winPtr.deallocate() }

    // MARK: Transport

    func connect() {
        state = .connecting
        guard pipe(&inFds) == 0, pipe(&outFds) == 0,
              let fin = fdopen(inFds[0], "r"), let fout = fdopen(outFds[1], "w") else {
            state = .failed("could not create mosh pipes")
            return
        }
        fIn = fin
        fOut = fout
        setvbuf(fout, nil, _IONBF, 0)   // unbuffered output → prompt rendering
        startReader()
        startEngine()
    }

    func send(_ bytes: [UInt8]) {
        let fd = inFds[1]
        guard fd >= 0 else { return }
        writeQueue.async {
            bytes.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
        }
    }

    func resize(cols: Int, rows: Int) {
        winPtr.pointee.ws_col = UInt16(max(1, cols))
        winPtr.pointee.ws_row = UInt16(max(1, rows))
        #if MOSH_ENABLED
        if let t = moshThread { pthread_kill(t, SIGWINCH) }
        #endif
    }

    func disconnect() {
        // Closing the write end of mosh's stdin and our read of its stdout unblocks mosh_main.
        for fd in inFds + outFds where fd >= 0 { close(fd) }
        inFds = [-1, -1]; outFds = [-1, -1]
        reader?.cancel()
        state = .disconnected(nil)
    }

    // MARK: - stdout reader → SwiftTerm

    private func startReader() {
        let fd = outFds[0]
        let t = Thread { [weak self] in
            var buf = [UInt8](repeating: 0, count: 8192)
            while !(Thread.current.isCancelled) {
                let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                if n <= 0 { break }
                self?.onReceive?(Array(buf[0..<n]))
            }
        }
        t.name = "MoshTransport.reader"
        t.stackSize = 1 << 20
        reader = t
        t.start()
    }

    // MARK: - mosh engine (GPL, opt-in)

    private func startEngine() {
        #if MOSH_ENABLED
        let ctx = Unmanaged.passRetained(self).toOpaque()
        var tid: pthread_t?
        let rc = pthread_create(&tid, nil, { arg in
            let me = Unmanaged<MoshTransport>.fromOpaque(arg).takeRetainedValue()
            me.runMoshMain()
            return nil
        }, ctx)
        if rc == 0 { moshThread = tid; state = .connected }
        else { state = .failed("pthread_create failed (\(rc))") }
        #else
        state = .failed("Mosh is not enabled in this build. See docs/MOSH_INTEGRATION.md to add mosh.xcframework.")
        #endif
    }

    #if MOSH_ENABLED
    private func runMoshMain() {
        let stateCB: @convention(c) (UnsafeRawPointer?, UnsafeRawPointer?, Int) -> Void = { ctx, buf, size in
            guard let ctx, let buf, size > 0 else { return }
            let me = Unmanaged<MoshTransport>.fromOpaque(ctx).takeUnretainedValue()
            me.stateBlob = Data(bytes: buf, count: size)
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        ip.withCString { ipC in port.withCString { portC in key.withCString { keyC in
        predictionMode.withCString { predC in "no".withCString { overC in
            _ = mosh_main(fIn, fOut, winPtr, stateCB, ctx,
                          ipC, portC, keyC, predC, nil, 0, overC)
        }}}}}
        state = .disconnected("mosh session ended")
    }
    #endif
}
