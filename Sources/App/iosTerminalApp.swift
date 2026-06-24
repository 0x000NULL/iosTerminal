import SwiftUI
import SwiftData

@main
struct iosTerminalApp: App {
    init() {
        // Process-global env for the in-process mosh client (matches Blink's app setup).
        // No terminfo DB needed — mosh emits hardcoded ANSI escapes.
        setenv("TERM", "xterm-256color", 1)
        setlocale(LC_ALL, "")
        setenv("LANG", "en_US.UTF-8", 1)

        if SettingsStore.bellMode == .notify {
            NotificationManager.shared.requestAuth()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: ConnectionProfile.self)
    }
}
