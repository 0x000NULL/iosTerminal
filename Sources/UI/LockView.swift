import SwiftUI

/// Full-screen cover shown (a) when the app isn't active — a privacy blank so the live terminal
/// isn't captured in the app-switcher snapshot — and (b) when app-lock is on and not yet unlocked.
struct LockView: View {
    var locked: Bool
    var onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Color(red: 0x3D/255, green: 0xFF/255, blue: 0x88/255))
                if locked {
                    Text("iosTerminal is locked").font(.headline)
                    Button(action: onUnlock) {
                        Label("Unlock", systemImage: "faceid")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .transition(.opacity)
    }
}
