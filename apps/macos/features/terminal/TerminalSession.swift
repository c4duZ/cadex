import CCadex
import Foundation

/// A shell session in the core (cadex_terminal_*). Used from the main thread;
/// the core calls back from its reader thread and this class hops to main.
@MainActor
public final class TerminalSession {
    public enum OpenError: Error {
        case failed(status: Int32)
    }

    /// New output arrived: redraw. Coalesced, so a burst of output from the
    /// shell causes one call per main-loop turn, not one per read.
    public var onOutput: (() -> Void)?
    /// The shell exited on its own, with its exit code.
    public var onExit: ((Int32) -> Void)?
    /// The program set the title (OSC 0/2); read it with title().
    public var onTitle: (() -> Void)?
    /// The program rang the bell.
    public var onBell: (() -> Void)?
    /// A local server's address showed up in the output (once each).
    public var onLocalURL: ((String) -> Void)?
    /// A program asked for a desktop notification: title and body.
    public var onNotification: ((String, String) -> Void)?
    /// An agent in the terminal reported its state (OSC 7501); read it with agentStatus().
    public var onAgentStatus: (() -> Void)?

    // Touched from deinit, which is not main-actor isolated. Safe because
    // cadex_terminal_close may be called from any thread.
    nonisolated(unsafe) private(set) var handle: OpaquePointer?
    private let relay: CallbackRelay

    /// A session the terminal daemon keeps (terminal.keepSessions): its
    /// socket, its name, and whether to take an existing one back.
    public struct Kept: Sendable {
        public let socket: String
        public let id: String
        public let attach: Bool
        public init(socket: String, id: String, attach: Bool) {
            self.socket = socket
            self.id = id
            self.attach = attach
        }
    }

    public init(cols: UInt16, rows: UInt16, cwd: String? = nil, shell: String? = nil, historyLines: UInt32 = 0,
                kept: Kept? = nil, replayPath: String? = nil) throws {
        relay = CallbackRelay()
        var options = cadex_terminal_options()
        options.cols = cols
        options.rows = rows
        options.history_lines = historyLines
        options.context = Unmanaged.passUnretained(relay).toOpaque()
        options.on_output = { context in CallbackRelay.from(context).outputArrived() }
        options.on_exit = { context, code in CallbackRelay.from(context).exited(code: code) }
        options.on_title = { context in CallbackRelay.from(context).onMain { $0.onTitle?() } }
        options.on_bell = { context in CallbackRelay.from(context).onMain { $0.onBell?() } }
        options.on_agent_status = { context in CallbackRelay.from(context).onMain { $0.onAgentStatus?() } }
        // On the reader thread: no closure inside (one would take the main
        // actor's isolation and trap here, found 2026-11-15).
        options.on_notification = { context, title, body in
            guard let title, let body else { return }
            let heading = String(cString: title)
            let text = String(cString: body)
            CallbackRelay.from(context).onMain { $0.onNotification?(heading, text) }
        }
        options.on_local_url = { context, url in
            guard let url else { return }
            let address = String(cString: url)
            CallbackRelay.from(context).onMain { $0.onLocalURL?(address) }
        }

        // The daemon's strings live until the open returns.
        let owned = [kept?.socket, kept?.id, replayPath].map { $0.flatMap { strdup($0) } }
        defer { owned.forEach { free($0) } }
        options.daemon_socket = UnsafePointer(owned[0])
        options.daemon_session = UnsafePointer(owned[1])
        options.daemon_attach = kept?.attach ?? false
        options.replay_path = UnsafePointer(owned[2])
        var opened: OpaquePointer?
        let status = withOptionalCString(cwd) { cwdPtr in
            withOptionalCString(shell) { shellPtr in
                options.cwd = cwdPtr
                options.shell = shellPtr
                return cadex_terminal_open(&options, &opened)
            }
        }
        guard status == CADEX_OK, let opened else { throw OpenError.failed(status: status) }
        handle = opened
        relay.session = self
    }

    deinit {
        cadex_terminal_close(handle)
    }

    /// What the agent in this terminal last reported (OSC 7501), or nil
    /// when none did (docs/adr/0022-terminal-daemon.md).
    public func agentStatus() -> TerminalAgentStatus? {
        guard let handle else { return nil }
        var raw = cadex_agent_status()
        guard cadex_terminal_agent_status(handle, &raw) == CADEX_OK,
              let state = TerminalAgentStatus.State(rawValue: raw.state), state != .none else { return nil }
        let app = withUnsafeBytes(of: &raw.app) { String(decoding: $0.prefix(Int(raw.app_len)), as: UTF8.self) }
        let message = withUnsafeBytes(of: &raw.msg) { String(decoding: $0.prefix(Int(raw.msg_len)), as: UTF8.self) }
        return TerminalAgentStatus(state: state, kind: TerminalAgentStatus.Kind(rawValue: raw.kind) ?? .none, app: app, message: message)
    }

    /// Ends the shell. No callback runs after this returns.
    public func close() {
        cadex_terminal_close(handle)
        handle = nil
    }

    /// Lets go of a session the daemon keeps, which goes on running there
    /// (closes it like close() when it is the session's own pty).
    public func detach() {
        cadex_terminal_detach(handle)
        handle = nil
    }

    public func write(_ bytes: [UInt8]) {
        guard let handle, !bytes.isEmpty else { return }
        _ = bytes.withUnsafeBufferPointer { cadex_terminal_write(handle, $0.baseAddress, $0.count) }
    }

    public func write(_ text: String) {
        write(Array(text.utf8))
    }

    /// A key the core encodes for the program's modes: CADEX_KEY_* and
    /// CADEX_MOD_*, the typed text without Ctrl and Option, and the key's
    /// character without Shift (or 0).
    public func key(_ key: UInt16, mods: UInt8, text: String = "", unshifted: UInt32 = 0) {
        guard let handle else { return }
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBufferPointer {
            cadex_terminal_key(handle, key, mods, $0.baseAddress, $0.count, unshifted)
        }
    }

    public func resize(cols: UInt16, rows: UInt16, cellWidth: UInt16, cellHeight: UInt16) {
        guard let handle, cols > 0, rows > 0 else { return }
        _ = cadex_terminal_resize(handle, cols, rows, cellWidth, cellHeight)
    }

    /// The current directory: what the shell reported (OSC 7), or the
    /// directory of the program in the foreground. Nil if unknown.
    public func workingDirectory() -> String? {
        guard let handle else { return nil }
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard cadex_terminal_copy_working_directory(handle, &bytes, &length) == CADEX_OK, let bytes else { return nil }
        defer { cadex_free(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    /// The cursor's default shape (CADEX_CURSOR_*) and blinking.
    func setCursor(shape: UInt8, blink: Bool) {
        guard let handle else { return }
        _ = cadex_terminal_set_cursor(handle, shape, blink)
    }

    /// The theme's colors become the terminal's defaults.
    func setColors(_ appearance: TerminalAppearance) {
        guard let handle else { return }
        var colors = appearance.coreColors
        _ = cadex_terminal_set_colors(handle, &colors)
    }

    /// The title the program set, empty if none.
    public func title() -> String {
        guard let handle else { return "" }
        var bytes: UnsafeMutablePointer<UInt8>?
        var length = 0
        guard cadex_terminal_copy_title(handle, &bytes, &length) == CADEX_OK, let bytes else { return "" }
        defer { cadex_free(bytes) }
        return String(decoding: UnsafeBufferPointer(start: bytes, count: length), as: UTF8.self)
    }

    public var hasForegroundProcess: Bool {
        guard let handle else { return false }
        return cadex_terminal_has_foreground_process(handle)
    }

    /// The foreground program's process group, 0 when the shell owns the
    /// terminal: an agent session's pid has it as its group (docs/spec/agents.md).
    public var foregroundGroup: Int32 {
        guard let handle else { return 0 }
        return cadex_terminal_foreground_group(handle)
    }

    /// The screen to draw. Valid until the next call; main thread only.
    func currentFrame() -> UnsafePointer<cadex_terminal_frame>? {
        guard let handle else { return nil }
        var frame: UnsafePointer<cadex_terminal_frame>?
        guard cadex_terminal_update_frame(handle, &frame) == CADEX_OK else { return nil }
        return frame
    }

    /// Milliseconds a synchronized update (DEC 2026) still holds the frame.
    var holdRemainingMs: UInt32 {
        guard let handle else { return 0 }
        return cadex_terminal_hold_remaining_ms(handle)
    }

    fileprivate func deliverOutput() { onOutput?() }
    fileprivate func deliverExit(_ code: Int32) { onExit?(code) }
}

/// Receives the core's callbacks on its reader thread and forwards them to
/// the main thread. Lives exactly as long as its session.
private final class CallbackRelay: @unchecked Sendable {
    weak var session: TerminalSession?
    private let lock = NSLock()
    private var outputPending = false

    static func from(_ context: UnsafeMutableRawPointer?) -> CallbackRelay {
        Unmanaged<CallbackRelay>.fromOpaque(context!).takeUnretainedValue()
    }

    func outputArrived() {
        lock.lock()
        let alreadyPending = outputPending
        outputPending = true
        lock.unlock()
        if alreadyPending { return }

        DispatchQueue.main.async { [self] in
            lock.lock()
            outputPending = false
            lock.unlock()
            MainActor.assumeIsolated { session?.deliverOutput() }
        }
    }

    func exited(code: Int32) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { session?.deliverExit(code) }
        }
    }

    /// Runs `body` on the main thread with the session, if it still exists.
    func onMain(_ body: @escaping @MainActor (TerminalSession) -> Void) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                if let session { body(session) }
            }
        }
    }
}

private func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    guard let string else { return body(nil) }
    return string.withCString { body($0) }
}
