import SwiftUI

/// Bridges a transport's synchronous host-key decision (called on a background thread) to a
/// SwiftUI alert. The background thread blocks on a semaphore until the user answers.
@MainActor
final class HostKeyPrompter: ObservableObject {
    struct Pending: Identifiable {
        let id = UUID()
        let key: HostKey
        let status: HostKeyStatus
        let respond: (Bool) -> Void
    }
    @Published var pending: Pending?

    /// Pass this to a transport's `hostKeyPrompt`. MUST be invoked off the main thread.
    nonisolated func decide(_ key: HostKey, _ status: HostKeyStatus) -> Bool {
        let sem = DispatchSemaphore(value: 0)
        let box = DecisionBox()
        Task { @MainActor in
            self.pending = Pending(key: key, status: status) { [weak self] ok in
                box.value = ok
                self?.pending = nil
                sem.signal()
            }
        }
        sem.wait()
        return box.value
    }
}

private final class DecisionBox { var value = false }
