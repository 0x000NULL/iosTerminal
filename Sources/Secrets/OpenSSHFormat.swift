import Foundation

/// Minimal SSH wire-format encoding (RFC 4251 `string`) for exporting public keys.
enum OpenSSHFormat {
    /// 4-byte big-endian length prefix + bytes.
    static func sshString(_ data: Data) -> Data {
        var out = Data()
        var len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(data)
        return out
    }

    static func sshString(_ s: String) -> Data { sshString(Data(s.utf8)) }

    /// An `authorized_keys` line for an ECDSA P-256 public key, given its X9.63 point
    /// (`0x04 || X || Y`, 65 bytes). Format: `ecdsa-sha2-nistp256 <base64 blob> <comment>`.
    static func ecdsaP256PublicKey(x963: Data, comment: String = "iosTerminal") -> String {
        var blob = Data()
        blob.append(sshString("ecdsa-sha2-nistp256"))
        blob.append(sshString("nistp256"))
        blob.append(sshString(x963))
        return "ecdsa-sha2-nistp256 \(blob.base64EncodedString()) \(comment)"
    }
}
