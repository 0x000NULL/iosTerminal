import Foundation
import LocalAuthentication

/// Session-level biometric gate. Authenticate **once per foreground session** to reveal
/// stored secrets; we then hold an authenticated `LAContext` so reconnect-on-roam never
/// re-prompts (the hostile-UX the red-team warned about). Uses `.userPresence`-equivalent
/// device-owner policy, not per-item `.biometryCurrentSet`.
@MainActor
final class BiometricGate: ObservableObject {
    static let shared = BiometricGate()

    @Published private(set) var unlocked = false
    private var context = LAContext()

    var biometryAvailable: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    /// Unlock for the session. Returns true if already unlocked or auth succeeds.
    func unlock(reason: String = "Unlock iosTerminal") async -> Bool {
        if unlocked { return true }
        let ctx = LAContext()
        ctx.localizedReason = reason
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No passcode/biometry enrolled (e.g. plain simulator) → don't hard-block a personal app.
            unlocked = true
            return true
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            if ok { context = ctx; unlocked = true }
            return ok
        } catch {
            return false
        }
    }

    /// Call when the app resigns active so the next foreground requires a fresh unlock.
    func lock() {
        unlocked = false
        context = LAContext()
    }
}
