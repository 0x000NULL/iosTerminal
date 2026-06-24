import SwiftUI

/// Ephemeral connect form (no save) — for one-off connections. Saved hosts go through
/// `ProfileEditView` + `HomeView`.
struct QuickConnectView: View {
    enum AuthKind: String, CaseIterable, Identifiable {
        case password = "Password"
        case key = "Private key"
        case tailscale = "Tailscale SSH"
        var id: String { rawValue }
    }

    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var useMosh = false
    @State private var authKind: AuthKind = .password
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""

    var body: some View {
        Form {
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
                    ForEach(AuthKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch authKind {
                case .password:
                    SecureField("Password", text: $password)
                case .key:
                    TextEditor(text: $privateKey)
                        .frame(height: 120)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    SecureField("Key passphrase (optional)", text: $passphrase)
                case .tailscale:
                    Text("No credential — tailnet identity authenticates. Needs Tailscale SSH on the host.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                NavigationLink {
                    TerminalSessionView(title: "\(username)@\(host)", makeTransport: build)
                } label: {
                    Label("Connect", systemImage: "terminal")
                }
                .disabled(!canConnect)
            }
        }
        .navigationTitle("Quick connect")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var canConnect: Bool {
        guard !host.isEmpty, !username.isEmpty else { return false }
        switch authKind {
        case .password: return !password.isEmpty
        case .key: return !privateKey.isEmpty
        case .tailscale: return true
        }
    }

    private func build(_ prompter: HostKeyPrompter) -> Transport {
        let auth: SSHAuth
        switch authKind {
        case .password: auth = .password(password)
        case .key: auth = .privateKey(pem: Data(privateKey.utf8), passphrase: passphrase.isEmpty ? nil : passphrase)
        case .tailscale: auth = .none
        }
        var cfg = SSHConfig(host: host, port: UInt16(port) ?? 22, username: username, auth: auth)
        cfg.initialCommand = "tmux new -A -s main"
        if useMosh {
            let t = MoshSessionTransport(sshConfig: cfg, moshExec: cfg.initialCommand)
            t.hostKeyPrompt = prompter.decide
            return t
        }
        let t = SSHTransport(config: cfg)
        t.hostKeyPrompt = prompter.decide
        return t
    }
}
