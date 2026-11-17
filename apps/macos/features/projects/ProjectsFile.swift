import Foundation
import Tabs

/// The projects as saved (docs/spec/projects.md): Application Support/Cadex/projects.json, written
/// whole and atomically, so a crash leaves the old file or the new one, never half of one.
public struct SavedProjects: Codable, Equatable, Sendable {
    public struct Project: Codable, Equatable, Sendable {
        public var name: String
        /// The project's folder: its repository (a task's worktree belongs to the main one).
        public var folder: String
        public var tabs: TabsSnapshot
        /// A work color's name ("blue"), plan 15, phase D.
        public var color: String?

        public init(name: String, folder: String, tabs: TabsSnapshot, color: String? = nil) {
            self.name = name
            self.folder = folder
            self.tabs = tabs
            self.color = color
        }
    }

    /// Bumped when the format changes in a way old files cannot be read.
    public var version = 1
    public var projects: [Project]
    public var active: Int
    /// The workspace folder (the explorer's root), for a launch without one: from the Dock there
    /// is never a folder argument.
    public var folder: String?

    public init(projects: [Project], active: Int, folder: String? = nil) {
        self.projects = projects
        self.active = active
        self.folder = folder
    }
}

/// spaces.json as plan 7 wrote it, read once to become projects.json (migration 0035).
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

public enum ProjectsFile {
    /// CADEX_PROJECTS_FILE points somewhere else: checking the app must not overwrite the owner's
    /// projects.
    public static var defaultURL: URL {
        if let path = ProcessInfo.processInfo.environment["CADEX_PROJECTS_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cadex/projects.json")
    }

    /// The saved projects; nil without a file. A file that does not read is moved aside
    /// (projects.bad-<date>.json) and the app starts fresh. Without projects.json, the spaces.json
    /// beside it becomes projects once and stays beside as spaces.migrated.json (the spec: the old
    /// file stays until the next plan).
    public static func load(from url: URL) -> SavedProjects? {
        guard let data = try? Data(contentsOf: url) else { return migrateLegacy(beside: url) }
        if let saved = try? JSONDecoder().decode(SavedProjects.self, from: data), !saved.projects.isEmpty {
            return saved
        }
        moveAside(url)
        return nil
    }

    public static func save(_ projects: SavedProjects, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: url, options: .atomic)
    }

    static func migrateLegacy(beside url: URL) -> SavedProjects? {
        let old = url.deletingLastPathComponent().appendingPathComponent("spaces.json")
        guard let data = try? Data(contentsOf: old), let legacy = try? JSONDecoder().decode(LegacySpaces.self, from: data),
              !legacy.spaces.isEmpty else { return nil }
        let projects = migrate(legacy, root: repositoryRoot) { snapshot in
            snapshot.items.lazy.compactMap { item -> String? in
                if case .terminal(_, let layout, _, _) = item { return layout.folders.first }
                return nil
            }.first.map(repositoryRoot)
        }
        guard (try? save(projects, to: url)) != nil else { return projects }
        try? FileManager.default.moveItem(at: old, to: old.deletingLastPathComponent().appendingPathComponent("spaces.migrated.json"))
        return projects
    }

    /// Each space becomes the project of its folder (its first terminal's repository, else the
    /// workspace's); spaces of the same folder become one project with the tabs of all, in order.
    /// Pure: the folder of a snapshot comes from `folderOf`.
    /// `root` takes the workspace's folder to its repository too (a workspace in a repository's
    /// subfolder and a space in its root are one project: review of 2026-11-17).
    static func migrate(_ legacy: LegacySpaces, root: (String) -> String = { $0 }, folderOf: (TabsSnapshot) -> String?) -> SavedProjects {
        var projects: [SavedProjects.Project] = []
        var activeFolder: String?
        let workspace = legacy.folder.map(root) ?? NSHomeDirectory()
        for (index, space) in legacy.spaces.enumerated() {
            let folder = folderOf(space.tabs) ?? workspace
            if index == legacy.active { activeFolder = folder }
            if let at = projects.firstIndex(where: { $0.folder == folder }) {
                projects[at].tabs.items += space.tabs.items
                continue
            }
            projects.append(.init(name: space.name, folder: folder, tabs: space.tabs, color: space.color))
        }
        let active = projects.firstIndex { $0.folder == activeFolder } ?? 0
        return SavedProjects(projects: projects, active: active, folder: legacy.folder)
    }

    /// The repository holding `path`: the folder with `.git` above it; a worktree's (`.git` is a
    /// file naming `<repo>/.git/worktrees/<name>`) is its main repository's. Files only, no git
    /// run (it runs while the app opens). Outside a repository, the path itself.
    public static func repositoryRoot(_ path: String) -> String {
        // realpath, as the shell reports folders (/tmp is /private/tmp); standardizingPath went
        // the other way and one folder had two names. A path that is gone stays as given.
        var dir = real(path)
        let fm = FileManager.default
        // Not above the home folder: a home kept in git (dotfiles) took every folder under it
        // into one project (review of 2026-11-17).
        let home = real(NSHomeDirectory())
        while dir != "/" && !dir.isEmpty && dir != home {
            let git = dir + "/.git"
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: git, isDirectory: &isDir) {
                if isDir.boolValue { return dir }
                if let text = try? String(contentsOfFile: git, encoding: .utf8),
                   let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) {
                    var gitdir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
                    // git 2.48's worktree.useRelativePaths writes it from the worktree's folder.
                    if !gitdir.hasPrefix("/") { gitdir = dir + "/" + gitdir }
                    if let range = gitdir.range(of: "/.git/worktrees/") { return real(String(gitdir[..<range.lowerBound])) }
                }
                return dir
            }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return real(path)
    }

    /// The path as the shell reports it (/tmp is /private/tmp); a path that is gone stays as given.
    static func real(_ path: String) -> String {
        realpath(path, nil).map { pointer in defer { free(pointer) }; return String(cString: pointer) } ?? path
    }

    static func moveAside(_ url: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent + ".bad-\(stamp)." + url.pathExtension
        try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent(name))
    }
}
