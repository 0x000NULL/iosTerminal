import Foundation
import Security

enum KeychainError: Error { case status(OSStatus) }

/// Stores secrets (passwords, private-key PEM, passphrases) as generic-password items with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Keyed by an opaque app-generated id so the
/// SwiftData profile only holds a reference, never the secret itself.
struct KeychainStore {
    static let shared = KeychainStore()
    private let service = "com.ethanaldrich.iosTerminal.secrets"

    func set(_ data: Data, for id: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func get(_ id: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    func delete(_ id: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(q as CFDictionary)
    }

    // Convenience for string secrets.
    func setString(_ s: String, for id: String) throws { try set(Data(s.utf8), for: id) }
    func getString(_ id: String) -> String? { get(id).flatMap { String(data: $0, encoding: .utf8) } }
}
