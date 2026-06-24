import Foundation
import CryptoKit

/// A non-extractable P-256 key held in the Secure Enclave (the only curve the Enclave
/// supports). The encrypted key blob is persisted in the Keychain under `tag`; the private
/// key never leaves the Enclave. Use `openSSHPublicKey` to register it in `authorized_keys`.
///
/// NOTE: Secure Enclave is **device-only** (unavailable on the simulator). The libssh2
/// sign-callback that uses `sign(_:)` to authenticate is the remaining device-side wiring
/// (see ProfileConnection / docs); generation + public-key export are complete here.
struct SecureEnclaveKey {
    let tag: String
    private let key: SecureEnclave.P256.Signing.PrivateKey

    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// Generate a new SE key and persist its representation in the Keychain.
    static func generate(tag: String, keychain: KeychainStore = .shared) throws -> SecureEnclaveKey {
        let key = try SecureEnclave.P256.Signing.PrivateKey()
        try keychain.set(key.dataRepresentation, for: tag)
        return SecureEnclaveKey(tag: tag, key: key)
    }

    /// Reload an existing SE key from the Keychain.
    init?(tag: String, keychain: KeychainStore = .shared) {
        guard let data = keychain.get(tag),
              let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data) else {
            return nil
        }
        self.tag = tag
        self.key = key
    }

    private init(tag: String, key: SecureEnclave.P256.Signing.PrivateKey) {
        self.tag = tag
        self.key = key
    }

    /// X9.63 representation of the public point: `0x04 || X || Y` (65 bytes for P-256).
    var x963PublicKey: Data { key.publicKey.x963Representation }

    /// `ecdsa-sha2-nistp256 <base64> <comment>` — paste into the server's authorized_keys.
    var openSSHPublicKey: String {
        OpenSSHFormat.ecdsaP256PublicKey(x963: x963PublicKey, comment: "iosTerminal-\(tag.prefix(8))")
    }

    /// ECDSA-SHA256 signature over `data` (used by the future libssh2 sign-callback).
    func sign(_ data: Data) throws -> P256.Signing.ECDSASignature {
        try key.signature(for: data)
    }
}
