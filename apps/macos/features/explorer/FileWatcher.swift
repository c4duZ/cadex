import Foundation
import CCadex

/// Watches the workspace through the core (FSEvents) and hands each batch
/// of changed folders to the main thread.
@MainActor
final class FileWatcher {
    struct Change: Equatable, Sendable {
        let path: String
        /// Detail was lost: read everything below again.
        let subtree: Bool
    }

    /// Read by deinit, which is not on the main actor; stopping is safe
    /// from any thread in the core.
    nonisolated(unsafe) private var handle: OpaquePointer?
    private let box: Box

    /// The core's callback runs on its watcher queue; this box carries the
    /// handler there and the changes back.
    fileprivate final class Box: @unchecked Sendable {
        let onChange: @MainActor ([Change]) -> Void
        init(_ onChange: @escaping @MainActor ([Change]) -> Void) { self.onChange = onChange }
    }

    /// Nil when the folder cannot be watched (outside the workspace, gone).
    init?(path: String, onChange: @escaping @MainActor ([Change]) -> Void) {
        box = Box(onChange)
        let context = Unmanaged.passUnretained(box).toOpaque()
        var out: OpaquePointer?
        let status = cadex_explorer_watch(path, context, fileWatcherCallback, &out)
        guard status == CADEX_OK, let out else { return nil }
        handle = out
    }

    /// Stops the core's watcher; its callback does not run after this. A
    /// batch already queued to the main thread still arrives, which is
    /// harmless: the box is kept alive by that block.
    func stop() {
        cadex_explorer_watch_stop(handle)
        handle = nil
    }

    deinit {
        cadex_explorer_watch_stop(handle)
    }
}

/// The core calls this on its watcher queue. A plain function, not a
/// closure inside the main-actor class: Swift 6 made that closure assert it
/// ran on the main thread and the app crashed on the first change
/// (EXC_BREAKPOINT in dispatch_assert_queue, 2026-10-19).
private func fileWatcherCallback(context: UnsafeMutableRawPointer?, changes: UnsafePointer<cadex_explorer_change>?, count: Int) {
    guard let context, let changes else { return }
    let box = Unmanaged<FileWatcher.Box>.fromOpaque(context).takeUnretainedValue()
    let list = (0..<count).map { FileWatcher.Change(path: String(cString: changes[$0].path), subtree: changes[$0].subtree) }
    DispatchQueue.main.async { MainActor.assumeIsolated { box.onChange(list) } }
}
