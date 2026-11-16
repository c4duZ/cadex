import Foundation

/// Where the Tailscale daemon of this Mac answers (docs/adr/0030-installed-tailscale.md).
public enum TailscaleEndpoint: Equatable, Sendable {
    /// The open `tailscaled`'s Unix socket (Homebrew or from source).
    case socket(String)
    /// The Standalone or App Store app: the LocalAPI on 127.0.0.1, with the
    /// same-user proof as the password.
    case local(port: Int, token: String)
    /// No LocalAPI found: the CLI's `status --json`. `beCLI`: the app's own
    /// binary, which acts as the CLI with TAILSCALE_BE_CLI=1.
    case cli(path: String, beCLI: Bool)
}

/// Finds the daemon in the ADR's order, stopping at the first one present:
/// the socket, the Standalone app's files, the App Store app's files, the
/// CLI. Reads only names, a link and the proof file; the paths are fields
/// so the tests point them at a temporary folder.
public struct TailscaleDaemon: Sendable {
    public var socketPath = "/var/run/tailscaled.socket"
    /// The Standalone app (`macsys`): `ipnport` links to the port, and
    /// `sameuserproof-<port>` holds the token (0640 root:admin; checked on
    /// this Mac, Tailscale 1.104.7, 2026-11-16).
    public var standaloneDir = "/Library/Tailscale"
    /// The App Store app keeps them in its group container, which macOS
    /// guards: the first read asks the owner once. Its files are named
    /// `sameuserproof-<port>-<token>`; not checked on a real App Store
    /// install (the owner has the Standalone one).
    public var groupContainers = NSHomeDirectory() + "/Library/Group Containers"
    public var appStoreGroupSuffix = "io.tailscale.ipn.macos"
    public var cliPaths = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale"]
    public var appBinary = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    public init() {}

    public func find() -> TailscaleEndpoint? {
        let files = FileManager.default
        if isSocket(socketPath) { return .socket(socketPath) }
        if let standalone = standalone() { return standalone }
        if let appStore = appStore() { return appStore }
        if let cli = cliPaths.first(where: { files.isExecutableFile(atPath: $0) }) { return .cli(path: cli, beCLI: false) }
        if files.isExecutableFile(atPath: appBinary) { return .cli(path: appBinary, beCLI: true) }
        return nil
    }

    func standalone() -> TailscaleEndpoint? {
        guard let link = try? FileManager.default.destinationOfSymbolicLink(atPath: standaloneDir + "/ipnport"),
              let port = Int(link.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port),
              let token = try? String(contentsOfFile: standaloneDir + "/sameuserproof-\(port)", encoding: .utf8)
        else { return nil }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : .local(port: port, token: trimmed)
    }

    func appStore() -> TailscaleEndpoint? {
        // Only the folder names are listed here: entering the container is
        // what macOS asks about, so it happens only for the App Store app's.
        guard let groups = try? FileManager.default.contentsOfDirectory(atPath: groupContainers),
              let group = groups.first(where: { $0.hasSuffix(appStoreGroupSuffix) }),
              let names = try? FileManager.default.contentsOfDirectory(atPath: groupContainers + "/" + group)
        else { return nil }
        for name in names.sorted() {
            let parts = name.split(separator: "-", maxSplits: 2)
            if parts.count == 3, parts[0] == "sameuserproof", let port = Int(parts[1]), (1...65535).contains(port), !parts[2].isEmpty {
                return .local(port: port, token: String(parts[2]))
            }
        }
        return nil
    }

    func isSocket(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFSOCK
    }
}
