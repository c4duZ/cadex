import Foundation
import Tabs

/// The spaces.json of the Cadex of before plan 27 (spaces, not projects), read once more on the
/// first launch after it. The reading left in plan 28 on the belief that every install had passed
/// through plan 27; the owner's had not (his 2.2.1 of 2026-10-22 straight to plan 40, 2026-11-20):
/// his tabs in bh-band/Bea and bkdg-center were simply not there. Now every folder of the old tabs
/// becomes a project, beside the ones projects.json already has.
struct LegacySpaces: Codable {
    struct Space: Codable {
        var name: String
        var tabs: TabsSnapshot
        var color: String?
    }
    var spaces: [Space]
    var active: Int
    var folder: String?
}

extension ProjectsFile {
    static let legacyName = "spaces.json"
    static let legacyDoneName = "spaces.migrated.json"

    /// `saved` with the projects the spaces.json beside `url` had and it lacks, then saved, and the
    /// spaces.json renamed spaces.migrated.json so it is read once. Without one, `saved` as is.
    static func mergeLegacy(_ saved: SavedProjects?, beside url: URL) -> SavedProjects? {
        let old = url.deletingLastPathComponent().appendingPathComponent(legacyName)
        guard let data = try? Data(contentsOf: old), let legacy = try? JSONDecoder().decode(LegacySpaces.self, from: data) else { return saved }
        let merged = merge(legacy, into: saved, root: repositoryRoot)
        guard (try? save(merged, to: url)) != nil else { return merged }
        try? FileManager.default.moveItem(at: old, to: old.deletingLastPathComponent().appendingPathComponent(legacyDoneName))
        return merged
    }

    /// Pure. Each folder of a pane of the old tabs, taken to its repository, is a project; a tab goes
    /// to the project of its first pane (a split of two repositories stays whole, in the first's).
    /// A project `saved` already has keeps its own tabs (the old shells are gone anyway); a new one
    /// gets its old tabs, or one terminal in its folder. New projects are pinned (the old ones stayed
    /// in the rail) and named after their folder. The home folder is no project (ADR 0038).
    static func merge(_ legacy: LegacySpaces, into saved: SavedProjects?, root: (String) -> String = { $0 },
                      home: String = NSHomeDirectory()) -> SavedProjects {
        var result = saved ?? SavedProjects(projects: [], active: 0, folder: legacy.folder)
        let items = legacy.spaces.flatMap(\.tabs.items)
        var order: [String] = []
        var tabsOf: [String: [TabsSnapshot.Item]] = [:]
        for item in items {
            guard case .terminal(_, let layout, _, _) = item else { continue }
            let roots = layout.folders.map(root)
            for folder in roots where !order.contains(folder) { order.append(folder) }
            if let first = roots.first { tabsOf[first, default: []].append(item) }
        }
        let had = Set(result.projects.map(\.folder))
        for folder in order where folder != home && !had.contains(folder) {
            let tabs = tabsOf[folder] ?? [.terminal(title: nil, layout: .pane(folder: folder), focus: 0)]
            let name = (folder as NSString).lastPathComponent
            result.projects.append(.init(name: name, folder: folder, tabs: TabsSnapshot(items: tabs, active: 0), pinned: true))
        }
        return result
    }
}
