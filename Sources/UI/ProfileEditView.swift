import SwiftUI
import SwiftData

/// Create or edit a saved host. Secrets are written to the Keychain (referenced by the
/// profile's `secretRef`), never stored in the model. Existing secrets are write-only:
/// leaving the field blank when editing keeps the stored value.
struct ProfileEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let profile: ConnectionProfile?   // nil = new

    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var useMosh = false
    @State private var authKind: ProfileAuthKind = .password
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var tmuxAttach = true
    @State private var tmuxSession = "main"
    @State private var startupCommand = ""
    @State private var predictionMode = "adaptive"
    @State private var moshLocale = "en_US.UTF-8"

    private var isEditing: Bool { profile != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name (optional)", text: $name)
                }
                Section("Host (Tailscale)") {
                    TextField("100.x.y.z  or  name.ts.net", text: $host)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $port).keyboardType(.numberPad)
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Use mosh (UDP roaming)", isOn: $useMosh)
                }
                Section("Authentication") {
                    Picker("Method", selection: $authKind) {
                        Text(ProfileAuthKind.password.label).tag(ProfileAuthKind.password)
                        Text(ProfileAuthKind.privateKey.label).tag(ProfileAuthKind.privateKey)
                        Text(ProfileAuthKind.tailscaleSSH.label).tag(ProfileAuthKind.tailscaleSSH)
                    }
                    .pickerStyle(.segmented)

                    switch authKind {
                    case .password:
                        SecureField(isEditing ? "Password (leave blank to keep)" : "Password", text: $password)
                    case .privateKey:
                        TextEditor(text: $privateKey)
                            .frame(height: 110)
                            .font(.system(.caption, design: .monospaced))
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        SecureField("Key passphrase (optional)", text: $passphrase)
                    case .tailscaleSSH:
                        Text("No credential needed — your tailnet identity authenticates. Requires `tailscale up --ssh` on the host (mosh bootstrap may not work over Tailscale SSH; prefer a real sshd for mosh).")
                            .font(.footnote).foregroundStyle(.secondary)
                    case .secureEnclave:
                        EmptyView()
                    }
                }
                Section("Session") {
                    Toggle("Auto-attach tmux", isOn: $tmuxAttach)
                    if tmuxAttach { TextField("tmux session", text: $tmuxSession) }
                    TextField("Custom startup command (optional)", text: $startupCommand)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if useMosh {
                    Section("Mosh") {
                        Picker("Local echo prediction", selection: $predictionMode) {
                            Text("Adaptive").tag("adaptive")
                            Text("Always").tag("always")
                            Text("Never").tag("never")
                        }
                        Text("\"Always\" feels snappiest on high-latency links; \"Never\" avoids predicted-then-corrected flicker in TUIs.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Picker("Server locale", selection: $moshLocale) {
                            Text("en_US.UTF-8").tag("en_US.UTF-8")
                            Text("C.UTF-8").tag("C.UTF-8")
                        }
                        Text("Must be a UTF-8 locale that exists on the host. Use C.UTF-8 for minimal/container hosts that lack en_US.UTF-8.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit host" : "New host")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) }
            }
            .onAppear(perform: load)
        }
    }

    private var valid: Bool {
        guard !host.isEmpty, !username.isEmpty else { return false }
        if isEditing { return true }   // keep existing secret if editing
        switch authKind {
        case .password: return !password.isEmpty
        case .privateKey: return !privateKey.isEmpty
        case .tailscaleSSH, .secureEnclave: return true
        }
    }

    private func load() {
        guard let p = profile else { return }
        name = p.name; host = p.host; port = String(p.port); username = p.username
        useMosh = p.useMosh; authKind = p.authKind
        tmuxAttach = p.tmuxAttach; tmuxSession = p.tmuxSession
        startupCommand = p.startupCommand ?? ""
        predictionMode = p.predictionMode
        moshLocale = p.moshLocale
    }

    private func save() {
        let p = profile ?? ConnectionProfile(name: name, host: host, username: username)
        p.name = name
        p.host = host
        p.port = Int(port) ?? 22
        p.username = username
        p.useMosh = useMosh
        p.authKind = authKind
        p.tmuxAttach = tmuxAttach
        p.tmuxSession = tmuxSession
        p.startupCommand = startupCommand.isEmpty ? nil : startupCommand
        p.predictionMode = predictionMode
        p.moshLocale = moshLocale

        switch authKind {
        case .password:
            if !password.isEmpty { try? KeychainStore.shared.setString(password, for: p.secretRef) }
        case .privateKey:
            if !privateKey.isEmpty { try? KeychainStore.shared.set(Data(privateKey.utf8), for: p.secretRef) }
            if !passphrase.isEmpty {
                try? KeychainStore.shared.setString(passphrase, for: p.passphraseRef)
                p.hasPassphrase = true
            } else if !isEditing {
                p.hasPassphrase = false
            }
        case .tailscaleSSH, .secureEnclave:
            break
        }

        if !isEditing { context.insert(p) }
        dismiss()
    }
}
