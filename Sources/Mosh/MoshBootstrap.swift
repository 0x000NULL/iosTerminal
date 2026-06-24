import Foundation

/// The UDP port + one-time key mosh-server prints on stdout.
struct MoshConnectInfo: Equatable {
    let port: String
    let key: String   // 22-char base64 of the 16-byte AES MOSH_KEY
}

/// Builds the `mosh-server` bootstrap command and parses its `MOSH CONNECT` reply.
enum MoshBootstrap {

    /// e.g. `mosh-server new -s -c 256 -l LANG=en_US.UTF-8 -l LC_ALL=en_US.UTF-8 -- tmux new -A -s main`
    static func serverCommand(colors: Int = 256,
                              locale: String = "en_US.UTF-8",
                              udpPort: String? = nil,
                              exec: String? = nil) -> String {
        var args = ["mosh-server", "new", "-s", "-c", String(colors),
                    "-l", "LANG=\(locale)", "-l", "LC_ALL=\(locale)"]
        if let p = udpPort { args += ["-p", p] }
        if let e = exec, !e.isEmpty { args += ["--", e] }
        return args.joined(separator: " ")
    }

    /// Parse `MOSH CONNECT <port> <key>` out of mosh-server output. Scans every line so a
    /// stray banner before the marker doesn't defeat us, but validates the port and 22-char key.
    static func parseConnect(_ output: String) -> MoshConnectInfo? {
        for raw in output.split(whereSeparator: \.isNewline) {
            let parts = raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 4, parts[0] == "MOSH", parts[1] == "CONNECT" else { continue }
            let port = parts[2], key = parts[3]
            guard let p = UInt16(port), p >= 1, key.count == 22 else { continue }
            return MoshConnectInfo(port: port, key: key)
        }
        return nil
    }
}
