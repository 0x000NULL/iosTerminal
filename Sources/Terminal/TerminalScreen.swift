import SwiftUI
import SwiftTerm

/// SwiftUI host for a terminal session: an `AppTerminalView` wired to a `Transport` (built
/// from a factory so it can reconnect), with the custom key bar as the input accessory.
struct TerminalScreen: UIViewRepresentable {
    /// Factory so each screen owns its transport. Defaults to the on-device demo shell.
    var makeTransport: () -> Transport = { LocalEchoTransport() }
    /// Connection-state sink (main queue).
    var onState: ((TransportState) -> Void)?
    /// Hands the coordinator back to the host so it can trigger reconnects.
    var onCoordinator: ((TerminalCoordinator) -> Void)?

    func makeCoordinator() -> TerminalCoordinator {
        let c = TerminalCoordinator(makeTransport: makeTransport)
        c.onState = onState
        return c
    }

    func makeUIView(context: Context) -> AppTerminalView {
        let terminal = AppTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        terminal.terminalDelegate = context.coordinator
        context.coordinator.terminal = terminal

        let width = terminal.window?.bounds.width ?? UIScreen.main.bounds.width
        terminal.inputAccessoryView = KeyBarView(terminal: terminal, width: width)

        onCoordinator?(context.coordinator)
        context.coordinator.start()
        return terminal
    }

    func updateUIView(_ uiView: AppTerminalView, context: Context) {}

    static func dismantleUIView(_ uiView: AppTerminalView, coordinator: TerminalCoordinator) {
        coordinator.transport.disconnect()
    }
}
