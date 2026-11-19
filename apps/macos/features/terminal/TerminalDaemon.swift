import CCadex
import Foundation

/// The terminal daemon from the app's side (docs/adr/0022-terminal-daemon.md,
/// plan 19 phase E2): where its program, socket and saved output are, starting
/// it once when a kept terminal opens, the names of this app's sessions, and
/// ending the ones no pane took back after a launch.
@MainActor
public final class TerminalDaemon {
    public static let shared = TerminalDaemon()

    /// This app's sessions start with it: another Cadex (a test instance,
    /// with its own projects file) never ends this one's. Set by the app.
    public var instance = "cadex"
    private var running = false

    init() {}

    var support: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].path + "/Cadex"
    }

    /// terminal-<protocol version>.sock in Cadex's sockets folder; CADEX_TERMINAL_SOCKET for tests.
    public var socket: String {
        ProcessInfo.processInfo.environment["CADEX_TERMINAL_SOCKET"] ?? support + "/sockets/terminal-1.sock"
    }

    /// Where the daemon saves each session's output when the Mac shuts down.
    /// Beside a test instance's socket (CADEX_TERMINAL_SOCKET): its daemon saved into the
    /// owner's folder when stopped (found 2026-11-19, plan 39's checks).
    var scrollback: String {
        if let socket = ProcessInfo.processInfo.environment["CADEX_TERMINAL_SOCKET"] {
            return (socket as NSString).deletingLastPathComponent + "/scrollback"
        }
        return support + "/scrollback"
    }

    /// cadex-terminald: in the bundle (Contents/Helpers), else in the core's build.
    var helper: String? {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cadex-terminald").path
        if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let built = root.path + "/core/zig-out/bin/cadex-terminald"
        return FileManager.default.isExecutableFile(atPath: built) ? built : nil
    }

    /// A daemon answers, started now if needed; false keeps the terminal on
    /// a pty of its own (nothing kept, as with the setting off).
    func ready() -> Bool {
        if running, FileManager.default.fileExists(atPath: socket) { return true }
        guard let helper else { return false }
        try? FileManager.default.createDirectory(atPath: (socket as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.createDirectory(atPath: scrollback, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        running = cadex_terminal_daemon_ensure(helper, socket, scrollback) == CADEX_OK
        return running
    }

    func newID() -> String { instance + "-" + UUID().uuidString.lowercased() }

    /// The output saved for `id` before the Mac restarted, if any.
    func savedOutput(_ id: String) -> String? {
        let path = scrollback + "/" + id + ".raw"
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    /// After the main window's spaces came back: this app's sessions that
    /// no pane took back end (nobody could see them again), and so does
    /// output saved for panes that are gone.
    public func closeUnclaimed(claimed: [String]) {
        let saved = (try? FileManager.default.contentsOfDirectory(atPath: scrollback)) ?? []
        for file in saved where file.hasPrefix(instance + "-") && file.hasSuffix(".raw") && !claimed.contains(String(file.dropLast(4))) {
            try? FileManager.default.removeItem(atPath: scrollback + "/" + file)
        }
        guard FileManager.default.fileExists(atPath: socket) else { return }
        let owned = claimed.map { strdup($0) }
        defer { owned.forEach { free($0) } }
        let pointers: [UnsafePointer<CChar>?] = owned.map { UnsafePointer($0) }
        _ = cadex_terminal_daemon_close_unclaimed(socket, instance + "-", pointers, UInt32(claimed.count), nil)
    }
}
