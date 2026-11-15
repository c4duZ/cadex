import Foundation

/// The hook went away before the owner answered: whoever waits on a
/// permission sets `onCancel` (main thread).
@MainActor
public final class AgentToolsCancel {
    public var onCancel: (() -> Void)?
    private var fired = false

    nonisolated init() {}

    func fire() {
        fired = true
        onCancel?()
    }

    /// Already gone when the waiter arrives.
    public var isCancelled: Bool { fired }
}

/// One answer to a hook at most: the click and the hook leaving race.
final class AgentToolsOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func take() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
