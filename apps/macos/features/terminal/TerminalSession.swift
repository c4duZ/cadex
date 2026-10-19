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

    // Touched from deinit, which is not main-actor isolated. Safe because
    // cadex_terminal_close may be called from any thread.
    nonisolated(unsafe) private var handle: OpaquePointer?
    private let relay: CallbackRelay

    public init(cols: UInt16, rows: UInt16, cwd: String? = nil, shell: String? = nil) throws {
        relay = CallbackRelay()
        var options = cadex_terminal_options()
        options.cols = cols
        options.rows = rows
        options.context = Unmanaged.passUnretained(relay).toOpaque()
        options.on_output = { context in CallbackRelay.from(context).outputArrived() }
        options.on_exit = { context, code in CallbackRelay.from(context).exited(code: code) }

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

    public func resize(cols: UInt16, rows: UInt16, cellWidth: UInt16, cellHeight: UInt16) {
        guard let handle, cols > 0, rows > 0 else { return }
        _ = cadex_terminal_resize(handle, cols, rows, cellWidth, cellHeight)
    }

    public var hasForegroundProcess: Bool {
        guard let handle else { return false }
        return cadex_terminal_has_foreground_process(handle)
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
}

private func withOptionalCString<R>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> R) -> R {
    guard let string else { return body(nil) }
    return string.withCString { body($0) }
}
