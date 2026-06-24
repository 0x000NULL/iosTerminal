import SwiftUI
import SwiftData

/// Root screen: saved hosts (SwiftData), quick-connect, and the demo shell.
struct HomeView: View {
    @Query(sort: \ConnectionProfile.createdAt, order: .reverse) private var profiles: [ConnectionProfile]
    @Environment(\.modelContext) private var context
    @State private var editing: ConnectionProfile?
    @State private var showingAdd = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if !profiles.isEmpty {
                    Section("Hosts") {
                        ForEach(profiles) { p in
                            NavigationLink { session(for: p) } label: { row(p) }
                                .swipeActions(allowsFullSwipe: false) {
                                    Button(role: .destructive) { delete(p) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button { editing = p } label: { Label("Edit", systemImage: "pencil") }
                                        .tint(.blue)
                                }
                        }
                    }
                }

                Section("Connect") {
                    NavigationLink { QuickConnectView() } label: {
                        Label("Quick connect (no save)", systemImage: "bolt")
                    }
                    NavigationLink {
                        TerminalSessionView(title: "Demo (no server)") { _ in LocalEchoTransport() }
                    } label: {
                        Label("Demo shell", systemImage: "ladybug")
                    }
                }

                Section {
                    Text("Run coding agents inside tmux (auto-attached as `main`) so sessions survive reconnects. See docs/SERVER_SETUP.md.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iosTerminal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add host")
                }
            }
            .sheet(isPresented: $showingAdd) { ProfileEditView(profile: nil) }
            .sheet(item: $editing) { p in ProfileEditView(profile: p) }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }

    private func row(_ p: ConnectionProfile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(p.name.isEmpty ? p.displayTitle : p.name).font(.headline)
                if p.useMosh {
                    Text("mosh").font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.tint.opacity(0.25), in: Capsule())
                }
            }
            Text(p.displayTitle + (p.port != 22 ? ":\(p.port)" : ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func session(for p: ConnectionProfile) -> some View {
        TerminalSessionView(title: p.displayTitle) { prompter in
            do { return try ProfileConnection.makeTransport(for: p, hostKeyPrompt: prompter.decide) }
            catch { return FailedTransport("\(error)") }
        }
    }

    private func delete(_ p: ConnectionProfile) {
        KeychainStore.shared.delete(p.secretRef)
        KeychainStore.shared.delete(p.passphraseRef)
        context.delete(p)
    }
}
