import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsStore.Key.fontSize) private var fontSize: Double = 14
    @AppStorage(SettingsStore.Key.appLock) private var appLock: Bool = true
    @AppStorage(SettingsStore.Key.bellMode) private var bellModeRaw: String = SettingsStore.BellMode.haptic.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Terminal") {
                    Stepper(value: $fontSize,
                            in: Double(SettingsStore.minFont)...Double(SettingsStore.maxFont),
                            step: 1) {
                        Text("Font size: \(Int(fontSize)) pt")
                    }
                    Text("Also adjustable in a session via pinch or the A-/A+ keys.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Security") {
                    Toggle("Require Face ID to open", isOn: $appLock)
                }
                Section("Terminal bell") {
                    Picker("On bell", selection: $bellModeRaw) {
                        ForEach(SettingsStore.BellMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: bellModeRaw) { _, new in
                        if new == SettingsStore.BellMode.notify.rawValue {
                            NotificationManager.shared.requestAuth()
                        }
                    }
                    Text("\"Notify\" posts a local notification when a job beeps while the app is backgrounded — handy for long coding agents runs.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
