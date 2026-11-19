import Foundation
import Memory

/// The repository's .ai-memory.toml in every project (plan 35 B; the owner, 2026-11-19): made when
/// a project opens (added, restored at launch, or from the recents) and when memory is turned on,
/// never over a file that exists, never for the home folder's loose terminals, only with
/// memory.enabled. Each folder is tried once per launch; the files are touched off the main thread
/// (every saved project comes back at launch).
@MainActor
enum MemoryMarkerWiring {
    /// The open projects' folders, every window's.
    private static var seen: Set<String> = []
    /// The folders already tried this launch.
    private static var tried: Set<String> = []
    /// memory.enabled, as SettingsBridge applies it.
    private static var enabled = false

    /// Settings applied: turning memory on makes the files of the projects already open.
    static func apply(enabled: Bool) {
        self.enabled = enabled
        flush()
    }

    /// The projects a window has now.
    static func note(_ folders: [String]) {
        seen.formUnion(folders)
        flush()
    }

    private static func flush() {
        guard enabled else { return }
        let new = seen.subtracting(tried)
        guard !new.isEmpty else { return }
        tried.formUnion(new)
        DispatchQueue.global(qos: .utility).async {
            for folder in new { MemoryMarker.ensure(folder: folder) }
        }
    }
}

extension WindowSession {
    /// The window's projects to MemoryMarkerWiring (projects.onChange: one opened, one shown).
    func noteMemoryMarkers() {
        MemoryMarkerWiring.note((projects?.projects ?? []).map(\.folder).filter { !Self.isLoose($0) })
    }
}
