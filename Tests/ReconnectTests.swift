import XCTest
@testable import iosTerminal

final class ReconnectTests: XCTestCase {
    @MainActor
    func testReconnectRebuildsTransportAndDetachesOld() {
        var built = 0
        let coord = TerminalCoordinator(makeTransport: { built += 1; return LocalEchoTransport() })
        let first = coord.transport
        XCTAssertEqual(built, 1)

        let term = AppTerminalView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        coord.terminal = term

        coord.reconnect()

        XCTAssertEqual(built, 2, "reconnect builds a fresh transport")
        XCTAssertFalse(coord.transport === first, "transport should be swapped")
        XCTAssertNil(first.onReceive, "old transport's callbacks must be detached so late bytes can't interleave")
        XCTAssertNil(first.onStateChange)
    }

    @MainActor
    func testReconnectIsDeDupedWhileInFlight() {
        var built = 0
        let coord = TerminalCoordinator(makeTransport: { built += 1; return LocalEchoTransport() })
        coord.terminal = AppTerminalView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        coord.reconnect()
        coord.reconnect()   // immediate second call should be ignored (in-flight guard)
        XCTAssertEqual(built, 2, "two near-simultaneous reconnects build only one new transport")
    }
}
