import CSSH

/// Thin namespace over the vendored libssh2 (CSSH = libssh2 1.11 + OpenSSL 1.1.1w).
/// Linking smoke test for now; the full `SSHTransport` is built on these C symbols next.
enum SSHLibrary {
    /// Must be called once before using libssh2. Returns true on success.
    @discardableResult
    static func initialize() -> Bool {
        libssh2_init(0) == 0
    }

    static func shutdown() {
        libssh2_exit()
    }

    /// e.g. "libssh2/1.11.0" — proves the binary links and the RSA-capable build is present.
    static var version: String {
        guard let v = libssh2_version(0) else { return "unknown" }
        return String(cString: v)
    }
}
