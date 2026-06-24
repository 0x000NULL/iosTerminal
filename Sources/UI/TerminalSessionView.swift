import SwiftUI

@MainActor
final class SessionViewModel: ObservableObject {
    @Published private(set) var state: TransportState = .idle
    weak var coordinator: TerminalCoordinator?

    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var active = true
    private let maxAttempts = 5

    /// Every transport state change flows through here; drives auto-retry with backoff.
    func update(_ s: TransportState) {
        state = s
        switch s {
        case .connected:
            cancelRetry()                                  // success — clear backoff
        case .connecting, .reconnecting:
            retryTask?.cancel(); retryTask = nil           // attempt in progress, keep the counter
        case .failed, .disconnected:
            scheduleRetry()
        case .idle:
            break
        }
    }

    /// Manual reconnect (toolbar) — resets the backoff.
    func reconnectNow() {
        cancelRetry()
        coordinator?.reconnect()
    }

    /// Foreground / network-change — reconnect only if the session is down.
    func reconnectIfNeeded() {
        switch state {
        case .disconnected, .failed: reconnectNow()
        default: break
        }
    }

    func teardown() {
        active = false
        cancelRetry()
    }

    func scrollToBottom() { coordinator?.terminal?.scrollToBottom() }
    func toggleKeyboard() { coordinator?.terminal?.toggleKeyboard() }
    func searchNext(_ t: String) { coordinator?.terminal?.searchNext(t) }
    func searchPrevious(_ t: String) { coordinator?.terminal?.searchPrevious(t) }
    func searchClear() { coordinator?.terminal?.searchClear() }

    private func cancelRetry() {
        retryTask?.cancel(); retryTask = nil; retryAttempt = 0
    }

    private func scheduleRetry() {
        guard active, retryTask == nil, retryAttempt < maxAttempts else { return }
        let seconds = UInt64(1) << retryAttempt            // 1, 2, 4, 8, 16
        retryAttempt += 1
        retryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            // Don't burn attempts while offline — a path change will re-trigger when back online.
            guard self.active, NetworkMonitor.shared.isOnline else { return }
            switch self.state {
            case .failed, .disconnected: self.coordinator?.reconnect()
            default: break
            }
        }
    }
}

/// Hosts a live terminal session: the SwiftTerm view, a status banner, host-key prompts, and
/// reconnect-on-foreground / on-network-change with backoff (tmux reattaches server-side).
struct TerminalSessionView: View {
    let title: String
    let makeTransport: (HostKeyPrompter) -> Transport

    @StateObject private var vm = SessionViewModel()
    @StateObject private var prompter = HostKeyPrompter()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSearch = false
    @State private var searchText = ""

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TerminalScreen(
                makeTransport: { makeTransport(prompter) },
                onState: { [vm] s in vm.update(s) },
                onCoordinator: { [vm] c in vm.coordinator = c }
            )
            .ignoresSafeArea(.container, edges: .bottom)
            VStack(spacing: 0) {
                if showSearch { searchBar }
                banner
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(title).font(.subheadline.monospaced()).lineLimit(1)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showSearch.toggle() } label: { Label("Search scrollback", systemImage: "magnifyingglass") }
                    Button { vm.scrollToBottom() } label: { Label("Scroll to bottom", systemImage: "arrow.down.to.line") }
                    Button { vm.toggleKeyboard() } label: { Label("Toggle keyboard", systemImage: "keyboard.chevron.compact.down") }
                    Button { vm.reconnectNow() } label: { Label("Reconnect", systemImage: "arrow.clockwise") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { vm.reconnectIfNeeded() }
        }
        .onAppear { NetworkMonitor.shared.onPathChange = { [vm] in vm.reconnectIfNeeded() } }
        .onDisappear {
            NetworkMonitor.shared.onPathChange = nil
            vm.teardown()
        }
        .alert(item: $prompter.pending) { pending in hostKeyAlert(pending) }
    }

    @ViewBuilder private var banner: some View {
        if case .connected = vm.state {
            EmptyView()
        } else {
            Text(vm.state.label)
                .font(.caption.monospaced())
                .foregroundStyle(isError ? .red : .primary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 8)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in scrollback", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onSubmit { vm.searchNext(searchText) }
            Button { vm.searchPrevious(searchText) } label: { Image(systemName: "chevron.up") }
            Button { vm.searchNext(searchText) } label: { Image(systemName: "chevron.down") }
            Button {
                showSearch = false; searchText = ""; vm.searchClear()
            } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
        }
        .font(.callout)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var isError: Bool {
        if case .failed = vm.state { return true }
        return false
    }

    private func hostKeyAlert(_ p: HostKeyPrompter.Pending) -> Alert {
        // CHANGED key = possible MITM. Make Reject the emphasised/default action and show BOTH
        // fingerprints so the user can compare the old (trusted) vs new key.
        if case .changed(let stored) = p.status {
            return Alert(
                title: Text("⚠️ Host key CHANGED"),
                message: Text("This server's key is DIFFERENT from the one you trusted — a possible man-in-the-middle. Only trust it if you know why it changed.\n\nWas:\n\(stored.fingerprint)\n\nNow (\(p.key.type)):\n\(p.key.fingerprint)"),
                primaryButton: .cancel(Text("Reject")) { p.respond(false) },
                secondaryButton: .destructive(Text("Trust new key")) { p.respond(true) }
            )
        }
        return Alert(
            title: Text("New host"),
            message: Text("First connection to this host. Verify the fingerprint if you can.\n\n\(p.key.type)\n\(p.key.fingerprint)"),
            primaryButton: .default(Text("Trust")) { p.respond(true) },
            secondaryButton: .cancel(Text("Cancel")) { p.respond(false) }
        )
    }
}
