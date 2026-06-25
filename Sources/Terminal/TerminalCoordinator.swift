import UIKit
import SwiftTerm

/// Bridges SwiftTerm's `TerminalView` to a `Transport`. Builds the transport from a factory
/// so it can be torn down and rebuilt (reconnect) against the *same* terminal view — preserving
/// scrollback — when the network changes or the app returns to the foreground.
final class TerminalCoordinator: NSObject, TerminalViewDelegate {
    private let makeTransport: () -> Transport
    private(set) var transport: Transport
    weak var terminal: AppTerminalView?

    /// Latest connection state, surfaced to the UI (main queue).
    var onState: ((TransportState) -> Void)?
    private(set) var lastState: TransportState = .idle

    // Inbound bytes are coalesced and fed to SwiftTerm on the MAIN thread: `feed()` can
    // synchronously manipulate the UIScrollView (contentOffset → Auto Layout) when output
    // scrolls, which aborts if done off the main thread. Coalescing avoids flooding main
    // under a firehose while preserving byte order.
    private let feedLock = NSLock()
    private var feedBuffer: [UInt8] = []
    private var feedScheduled = false

    init(makeTransport: @escaping () -> Transport) {
        self.makeTransport = makeTransport
        self.transport = makeTransport()
        super.init()
        wire(transport)
    }

    private func wire(_ t: Transport) {
        t.onReceive = { [weak self] bytes in self?.enqueueFeed(bytes) }
        t.onStateChange = { [weak self] s in
            self?.lastState = s
            // The view lays out (and reports its real cols/rows) within ms, but the SSH/mosh
            // bootstrap finishes ~seconds later — so the early sizeChanged() can land before the
            // PTY/mosh engine exists and get dropped, leaving the server at its default 80x24
            // (tmux then wraps/clips into the narrower phone display). Re-push the current view
            // size the instant the session reports connected so the server matches the screen.
            if case .connected = s { self?.pushCurrentSize() }
            self?.onState?(s)
        }
    }

    /// Push the terminal's current cols/rows to the live transport (main thread — `getTerminal()`
    /// reads view geometry). Safe to call repeatedly; idempotent on the server side.
    private func pushCurrentSize() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let term = self.terminal?.getTerminal() else { return }
            self.transport.resize(cols: term.cols, rows: term.rows)
        }
    }

    private func enqueueFeed(_ bytes: [UInt8]) {
        feedLock.lock()
        feedBuffer.append(contentsOf: bytes)
        let needsSchedule = !feedScheduled
        if needsSchedule { feedScheduled = true }
        feedLock.unlock()
        if needsSchedule {
            DispatchQueue.main.async { [weak self] in self?.drainFeed() }
        }
    }

    /// Main thread: drain all bytes accumulated since the last tick into a single feed.
    /// `feed()` already schedules a throttled (60fps), coalesced redraw via queuePendingDisplay,
    /// and the opaque-background fix in AppTerminalView is what prevents ghosting — so no extra
    /// setNeedsDisplay is needed (it would just force redundant un-throttled full redraws).
    private func drainFeed() {
        feedLock.lock()
        let chunk = feedBuffer
        feedBuffer.removeAll(keepingCapacity: true)
        feedScheduled = false
        feedLock.unlock()
        if let term = terminal, !chunk.isEmpty {
            term.feed(byteArray: chunk[...])
        }
    }

    func start() { transport.connect() }

    private var reconnecting = false

    /// Tear down the current transport and start a fresh one against the same terminal (scrollback
    /// preserved). De-dupes near-simultaneous calls (scenePhase .active + a network path change).
    func reconnect() {
        guard !reconnecting else { return }
        reconnecting = true

        // Detach the dying transport so its late bytes/state can't interleave into the new session.
        let old = transport
        old.onReceive = nil
        old.onStateChange = nil
        old.disconnect()
        feedLock.lock(); feedBuffer.removeAll(keepingCapacity: true); feedScheduled = false; feedLock.unlock()

        let t = makeTransport()
        transport = t
        wire(t)
        if let term = terminal?.getTerminal() {
            t.connect()
            t.resize(cols: term.cols, rows: term.rows)   // match the new PTY to the current view
        } else {
            t.connect()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.reconnecting = false }
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        transport.send(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        transport.resize(cols: newCols, rows: newRows)
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let s = String(data: content, encoding: .utf8) { UIPasteboard.general.string = s }
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    private lazy var bellGenerator = UIImpactFeedbackGenerator(style: .medium)
    private var lastBellTime: TimeInterval = 0

    func bell(source: TerminalView) {
        switch SettingsStore.bellMode {
        case .haptic:
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastBellTime > 0.3 {     // throttle bursts (tmux activity bells)
                lastBellTime = now
                bellGenerator.impactOccurred()
            }
        case .notify:
            NotificationManager.shared.notifyBell()
        case .off:
            break
        }
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
