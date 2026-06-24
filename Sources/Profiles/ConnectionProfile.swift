import Foundation
import SwiftData

enum ProfileAuthKind: String, Codable, CaseIterable, Identifiable {
    case password, privateKey, tailscaleSSH, secureEnclave
    var id: String { rawValue }
    var label: String {
        switch self {
        case .password: return "Password"
        case .privateKey: return "Private key"
        case .tailscaleSSH: return "Tailscale SSH"
        case .secureEnclave: return "Secure Enclave key"
        }
    }
    /// Whether this method needs a stored credential.
    var needsSecret: Bool {
        switch self {
        case .password, .privateKey: return true
        case .tailscaleSSH, .secureEnclave: return false
        }
    }
}

/// A saved connection. Secrets live in the Keychain (referenced by `secretRef`); the model
/// never stores a password or private key directly.
@Model
final class ConnectionProfile {
    var id: UUID = UUID()
    var name: String = ""
    var host: String = ""
    var port: Int = 22
    var username: String = ""
    var useMosh: Bool = false
    var authKindRaw: String = ProfileAuthKind.password.rawValue
    var secretRef: String = UUID().uuidString   // Keychain id (or Secure-Enclave key tag)
    var hasPassphrase: Bool = false
    var termType: String = "xterm-256color"
    var tmuxAttach: Bool = true
    var tmuxSession: String = "main"
    var startupCommand: String?
    var predictionMode: String = "adaptive"   // mosh --predict: adaptive | always | never
    var createdAt: Date = Date()
    var lastUsedAt: Date?

    init(name: String, host: String, port: Int = 22, username: String, useMosh: Bool = false) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.useMosh = useMosh
        self.secretRef = UUID().uuidString
        self.createdAt = Date()
    }

    var authKind: ProfileAuthKind {
        get { ProfileAuthKind(rawValue: authKindRaw) ?? .password }
        set { authKindRaw = newValue.rawValue }
    }

    var passphraseRef: String { secretRef + ".pp" }

    var displayTitle: String { "\(username)@\(host)" }

    /// The command the SSH shell should auto-run (tmux attach, or a custom startup).
    var initialCommand: String? {
        if tmuxAttach { return "tmux new -A -s \(tmuxSession)" }
        return startupCommand
    }
}
