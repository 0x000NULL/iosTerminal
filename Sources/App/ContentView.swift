import SwiftUI

struct ContentView: View {
    @StateObject private var gate = BiometricGate.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            HomeView()
            cover
        }
        .animation(.easeInOut(duration: 0.15), value: scenePhase)
        .animation(.easeInOut(duration: 0.15), value: gate.unlocked)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                Task { await unlockIfNeeded() }
            case .background:
                if SettingsStore.appLockEnabled { gate.lock() }
            default:
                break
            }
        }
    }

    /// Privacy cover when inactive/backgrounded; lock screen when app-lock is on and not unlocked.
    @ViewBuilder private var cover: some View {
        if scenePhase != .active {
            LockView(locked: false, onUnlock: {})          // privacy blank for the switcher snapshot
        } else if SettingsStore.appLockEnabled && !gate.unlocked {
            LockView(locked: true) { Task { await unlockIfNeeded() } }
        }
    }

    private func unlockIfNeeded() async {
        guard SettingsStore.appLockEnabled, !gate.unlocked else { return }
        _ = await gate.unlock(reason: "Unlock iosTerminal")
    }
}

#Preview {
    ContentView()
}
