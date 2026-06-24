import XCTest
import SwiftTerm
@testable import iosTerminal

/// Captures the bytes a terminal would send to the host.
private final class CapturingDelegate: NSObject, TerminalViewDelegate {
    var sent: [UInt8] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) { sent.append(contentsOf: data) }
    func reset() { sent = [] }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

final class KeyMappingTests: XCTestCase {
    private var term: AppTerminalView!
    private var cap: CapturingDelegate!

    override func setUp() {
        super.setUp()
        term = AppTerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        cap = CapturingDelegate()
        term.terminalDelegate = cap
    }

    private func bytes(_ action: () -> Void) -> [UInt8] {
        cap.reset(); action(); return cap.sent
    }

    func testImmediateKeys() {
        XCTAssertEqual(bytes { term.keyEsc() }, [0x1b])
        XCTAssertEqual(bytes { term.keyTab() }, [0x09])
        XCTAssertEqual(bytes { term.keyBackTab() }, [0x1b, 0x5b, 0x5a])   // ESC [ Z
        XCTAssertEqual(bytes { term.keyNewline() }, [0x0a])              // Ctrl-J
        XCTAssertEqual(bytes { term.keyTmuxPrefix() }, [0x02])          // Ctrl-B
        XCTAssertEqual(bytes { term.keyInterrupt() }, [0x03])          // Ctrl-C
    }

    func testArrowsNormalCursorMode() {
        term.getTerminal().applicationCursor = false
        XCTAssertEqual(bytes { term.keyArrow(.up) }, [0x1b, 0x5b, 0x41])    // ESC [ A
        XCTAssertEqual(bytes { term.keyArrow(.down) }, [0x1b, 0x5b, 0x42])
        XCTAssertEqual(bytes { term.keyArrow(.right) }, [0x1b, 0x5b, 0x43])
        XCTAssertEqual(bytes { term.keyArrow(.left) }, [0x1b, 0x5b, 0x44])
    }

    func testArrowsApplicationCursorMode() {
        term.getTerminal().applicationCursor = true
        XCTAssertEqual(bytes { term.keyArrow(.up) }, [0x1b, 0x4f, 0x41])    // ESC O A
        XCTAssertEqual(bytes { term.keyArrow(.left) }, [0x1b, 0x4f, 0x44])
    }

    func testControlArrowConsumesOneShot() {
        term.getTerminal().applicationCursor = false
        term.cycleControl(lock: false)                                     // Ctrl one-shot
        XCTAssertEqual(term.controlSticky, .oneShot)
        XCTAssertEqual(bytes { term.keyArrow(.right) }, [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x43]) // ESC [ 1 ; 5 C
        XCTAssertEqual(term.controlSticky, .off, "one-shot Ctrl should clear after the modified key")
    }

    func testControlLockedArrowPersists() {
        term.getTerminal().applicationCursor = false
        term.cycleControl(lock: true)                                      // Ctrl lock
        XCTAssertEqual(term.controlSticky, .locked)
        _ = bytes { term.keyArrow(.left) }
        XCTAssertEqual(term.controlSticky, .locked, "locked Ctrl should persist across modified keys")
    }

    func testStickyToggleTransitions() {
        XCTAssertEqual(term.controlSticky, .off)
        term.cycleControl(lock: false); XCTAssertEqual(term.controlSticky, .oneShot)
        term.cycleControl(lock: false); XCTAssertEqual(term.controlSticky, .off)
        term.cycleControl(lock: true);  XCTAssertEqual(term.controlSticky, .locked)
        term.cycleControl(lock: true);  XCTAssertEqual(term.controlSticky, .off)
    }
}
