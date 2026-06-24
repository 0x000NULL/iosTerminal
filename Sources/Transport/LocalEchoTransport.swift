import Foundation

/// A self-contained demo transport that emulates a tiny interactive shell entirely
/// on-device. It lets us exercise the terminal view and the on-screen key bar in the
/// simulator with **no server**, before SSH/Mosh exist.
///
/// Behaviour: prints a banner + prompt, echoes printable input, renders control bytes
/// as `^X`, turns CR into CR/LF + a fresh prompt, handles DEL as destructive backspace,
/// and visibly labels arrows/Tab so the key bar can be verified by eye.
final class LocalEchoTransport: Transport {
    private(set) var state: TransportState = .idle {
        didSet { let s = state; DispatchQueue.main.async { self.onStateChange?(s) } }
    }
    var onReceive: (([UInt8]) -> Void)?
    var onStateChange: ((TransportState) -> Void)?

    /// All work runs here, mirroring the real transports' serial-queue contract.
    private let queue = DispatchQueue(label: "LocalEchoTransport")
    private let prompt = "iosTerminal:~ $ "

    func connect() {
        state = .connecting
        queue.async {
            self.state = .connected
            self.emit("\u{1b}[1;32mWelcome to iosTerminal (local demo)\u{1b}[0m\r\n")
            self.emit("No server yet — this echoes input so you can test the key bar.\r\n")
            self.emit("Try: Ctrl, Alt, Esc, Tab, ⇧Tab, arrows, ⏎.\r\n\r\n")
            self.emit(self.prompt)
        }
    }

    func send(_ bytes: [UInt8]) {
        // Never block the caller (main thread): hop to the serial queue immediately.
        queue.async { self.handle(bytes) }
    }

    func resize(cols: Int, rows: Int) { /* demo: nothing to do */ }

    func disconnect() {
        queue.async { self.state = .disconnected(nil) }
    }

    // MARK: - Internals

    private func handle(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            switch b {
            case 0x0d, 0x0a: // CR / LF
                emit("\r\n" + prompt)
            case 0x7f, 0x08: // DEL / BS — destructive backspace
                emit("\u{08} \u{08}")
            case 0x1b: // ESC — could begin an arrow/CSI sequence; label what we recognise
                let consumed = renderEscapeSequence(bytes, from: i)
                i += consumed - 1
            case 0x09: // Tab
                emit("\u{1b}[2m⇥\u{1b}[0m")
            case 0x20...0x7e: // printable ASCII
                emit(String(UnicodeScalar(b)))
            case 0x00...0x1f: // other control bytes → ^X
                emit("\u{1b}[2m^\(String(UnicodeScalar(b | 0x40)))\u{1b}[0m")
            default:
                emit(String(UnicodeScalar(b)))
            }
            i += 1
        }
    }

    /// Recognise a few common ESC-prefixed sequences for the demo and return how many
    /// input bytes were consumed (always >= 1).
    private func renderEscapeSequence(_ bytes: [UInt8], from start: Int) -> Int {
        let rest = bytes[start...]
        // Arrows: ESC [ A/B/C/D  or  ESC O A/B/C/D
        if rest.count >= 3, rest[rest.startIndex + 1] == 0x5b || rest[rest.startIndex + 1] == 0x4f {
            let final = rest[rest.startIndex + 2]
            let name: String?
            switch final {
            case 0x41: name = "↑"
            case 0x42: name = "↓"
            case 0x43: name = "→"
            case 0x44: name = "←"
            case 0x5a: name = "⇧⇥"        // ESC [ Z
            default: name = nil
            }
            if let name {
                emit("\u{1b}[2m\(name)\u{1b}[0m")
                return 3
            }
        }
        // Bare ESC or Alt-prefix: show a small marker, consume just the ESC.
        emit("\u{1b}[2m⎋\u{1b}[0m")
        return 1
    }

    private func emit(_ text: String) {
        onReceive?(Array(text.utf8))
    }
}
