import CoreServices
import Foundation

/// The automations' folder watched while automations are on: a file made, changed or removed by
/// hand or by an agent counts at once (the page and the launchd dates follow; the owner,
/// 2026-11-22). FSEvents on the folder, which also reports a file written in place (an editor's
/// save, an agent's write), with a second of latency: a burst of saves is one change.
@MainActor
public final class AutomationFilesWatch {
    public static let shared = AutomationFilesWatch()
    private var stream: FSEventStreamRef?
    private var changed: (() -> Void)?

    public var isWatching: Bool { stream != nil }

    /// Watches `folder` (made when missing), calling `changed` on the main thread.
    public func start(folder: String, changed: @escaping () -> Void) {
        stop()
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        self.changed = changed
        var context = FSEventStreamContext()
        let callback: FSEventStreamCallback = { _, _, _, _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { AutomationFilesWatch.shared.changed?() } }
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes)) else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        changed = nil
    }
}
