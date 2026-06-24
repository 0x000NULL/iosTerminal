import Foundation

enum ProfileError: Error, CustomStringConvertible {
    case missingSecret
    case secureEnclaveNotWired

    var description: String {
        switch self {
        case .missingSecret: return "No stored secret for this profile."
        case .secureEnclaveNotWired: return "Secure Enclave auth is not enabled in this build yet."
        }
    }
}

/// Builds a `Transport` from a saved profile, resolving secrets from the Keychain.
enum ProfileConnection {
    static func makeTransport(for p: ConnectionProfile,
                              keychain: KeychainStore = .shared,
                              hostKeyPrompt: ((HostKey, HostKeyStatus) -> Bool)? = nil) throws -> Transport {
        let auth = try resolveAuth(p, keychain: keychain)
        var cfg = SSHConfig(host: p.host, port: UInt16(p.port), username: p.username, auth: auth)
        cfg.termType = p.termType
        cfg.initialCommand = p.initialCommand
        if p.useMosh {
            let t = MoshSessionTransport(sshConfig: cfg, moshExec: p.initialCommand,
                                         predictionMode: p.predictionMode, locale: p.moshLocale)
            t.hostKeyPrompt = hostKeyPrompt
            return t
        }
        let t = SSHTransport(config: cfg)
        t.hostKeyPrompt = hostKeyPrompt
        return t
    }

    static func resolveAuth(_ p: ConnectionProfile, keychain: KeychainStore) throws -> SSHAuth {
        switch p.authKind {
        case .password:
            guard let pw = keychain.getString(p.secretRef) else { throw ProfileError.missingSecret }
            return .password(pw)
        case .privateKey:
            guard let pem = keychain.get(p.secretRef) else { throw ProfileError.missingSecret }
            let pass = p.hasPassphrase ? keychain.getString(p.passphraseRef) : nil
            return .privateKey(pem: pem, passphrase: pass)
        case .tailscaleSSH:
            return .none
        case .secureEnclave:
            throw ProfileError.secureEnclaveNotWired
        }
    }
}
