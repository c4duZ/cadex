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

    // Touched from deinit, which is not main-actor isolated. Safe because
    // cadex_terminal_close may be called from any thread.
    nonisolated(unsafe) private(set) var handle: OpaquePointer?
    private let relay: CallbackRelay

    public init(cols: UInt16, rows: UInt16, cwd: String? = nil, shell: String? = nil, historyLines: UInt32 = 0) throws {
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
        options.on_local_url = { context, url in
            guard let url else { return }
            let address = String(cString: url)
            CallbackRelay.from(context).onMain { $0.onLocalURL?(address) }
        }

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

    /// Ends the shell. No callback runs after this returns.
    public func close() {
        cadex_terminal_close(handle)
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
