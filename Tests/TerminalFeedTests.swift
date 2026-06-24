import XCTest
@testable import iosTerminal

/// Regression guard for the device crash: feeding scrolling output from a background thread
/// must not touch UIKit/Auto Layout off the main thread. `TerminalCoordinator` coalesces
/// inbound bytes onto the main thread; this test drives that path with a real on-screen view.
final class TerminalFeedTests: XCTestCase {

    @MainActor
    func testBackgroundScrollingFeedRoutesToMainAndDoesNotCrash() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 120))
        let coord = TerminalCoordinator(makeTransport: { LocalEchoTransport() })
        let term = AppTerminalView(frame: window.bounds)
        term.terminalDelegate = coord
        coord.terminal = term
        window.addSubview(term)
        window.isHidden = false
        term.layoutIfNeeded()

        // Inbound from a BACKGROUND thread — enough lines to force scrolling (the pre-fix abort).
        let onReceive = coord.transport.onReceive
        let fed = expectation(description: "background feed enqueued")
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0 ..< 400 { onReceive?(Array("line \(i)\r\n".utf8)) }
            DispatchQueue.main.async { fed.fulfill() }
        }
        wait(for: [fed], timeout: 15)

        // Let queued main-thread feeds drain.
        let settle = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settle.fulfill() }
        wait(for: [settle], timeout: 5)
    }
}
