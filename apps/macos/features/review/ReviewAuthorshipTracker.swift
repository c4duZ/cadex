import Foundation

/// One worktree's authorship (docs/adr/0027-local-authorship.md): an agent's
/// edit marks its lines; a change on disk with no event is compared with
/// the last version known and the lines it touched become the owner's. Kept
/// in `<dir>/<repo>/<worktree>-authorship.json` (ranges, never text), the
/// last versions in `<worktree>-versions/`, only while the worktree exists,
/// at most 2 MB a file and 50 MB a worktree; past that, a file stops.
@MainActor
public final class ReviewAuthorshipTracker {
    public static let fileLimit = 2 * 1024 * 1024
    public static let worktreeLimit = 50 * 1024 * 1024
    public let root: String
    let file: String
    let versions: String
    public private(set) var files: [String: FileAuthorship] = [:]
    /// The marks changed (the review draws them again).
    public var onChange: (() -> Void)?

    /// `root`: the worktree's folder; `repo`, `worktree`: the names its files go under.
    public init(root: String, repo: String, worktree: String, dir: String? = nil) {
        self.root = root
        let store = ReviewCommentStore(repo: repo, worktree: worktree + "-authorship", dir: dir)
        file = store.path
        versions = (store.path as NSString).deletingPathExtension.replacingOccurrences(of: "-authorship", with: "-versions")
        if let data = FileManager.default.contents(atPath: file), let read = try? JSONDecoder().decode([String: FileAuthorship].self, from: data) { files = read }
    }

    /// An agent edited `path` (absolute): `lines` it wrote, or all of it.
    public func record(path: String, lines: [ClosedRange<Int>], whole: Bool, session: String) {
        guard let relative = relative(path), files[relative]?.stopped != true else { return }
        guard let now = read(path) else {
            // Too big (or gone): its authorship stops, said in the margin.
            if FileManager.default.fileExists(atPath: path) { files[relative] = FileAuthorship(agent: [], stopped: true); save() }
            return
        }
        var entry = files[relative] ?? FileAuthorship()
        if let before = version(relative) { entry.agent = Authorship.carry(entry.agent, from: before, to: now) }
        let added = whole ? (now.isEmpty ? [] : [1...now.count]) : lines.map { $0.clamped(to: 1...max(now.count, 1)) }
        entry.agent = Authorship.add(entry.agent, lines: added, session: session)
        files[relative] = entry
        keep(relative, now)
        save()
    }

    /// Files changed on disk (the watcher, or the review reading again):
    /// the tracked ones in those folders are compared with their last version.
    public func diskChanged(folders: [String]? = nil) {
        var changed = false
        for (relative, entry) in files where !entry.stopped {
            let path = root + "/" + relative
            if let folders, !folders.contains((path as NSString).deletingLastPathComponent) { continue }
            guard let before = version(relative) else { continue }
            guard let now = read(path) else {
                files[relative] = nil
                changed = true
                continue
            }
            guard now != before else { continue }
            files[relative]?.agent = Authorship.carry(entry.agent, from: before, to: now)
            keep(relative, now)
            changed = true
        }
        if changed { save() }
    }

    /// The agent's lines of a file (relative to the worktree), line → session.
    public func marks(of relative: String) -> [Int: String] {
        files[relative].map { Authorship.lines(of: $0.agent) } ?? [:]
    }

    /// review.export-authorship: the files, their ranges and sessions.
    public func export() -> Data? {
        let list = files.keys.sorted().map { ["path": $0, "ranges": files[$0]!.agent.map { ["start": $0.start, "end": $0.end, "session": $0.session] }] as [String: Any] }
        return try? JSONSerialization.data(withJSONObject: ["worktree": root, "files": list], options: [.prettyPrinted, .sortedKeys])
    }

    /// The worktree is gone: its authorship and versions go too.
    public func forget() {
        try? FileManager.default.removeItem(atPath: file)
        try? FileManager.default.removeItem(atPath: versions)
        files = [:]
        onChange?()
    }

    // MARK: Disk

    func relative(_ path: String) -> String? {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : nil
    }

    private func read(_ path: String) -> [String]? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.size] as? Int ?? 0) <= Self.fileLimit,
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return Self.lines(String(decoding: data, as: UTF8.self))
    }

    static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    private func versionPath(_ relative: String) -> String {
        versions + "/" + relative.replacingOccurrences(of: "%", with: "%25").replacingOccurrences(of: "/", with: "%2F")
    }

    private func version(_ relative: String) -> [String]? {
        FileManager.default.contents(atPath: versionPath(relative)).map { Self.lines(String(decoding: $0, as: UTF8.self)) }
    }

    /// The last version known, unless the worktree's versions would pass 50 MB.
    private func keep(_ relative: String, _ lines: [String]) {
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        let used = (try? FileManager.default.contentsOfDirectory(atPath: versions))?
            .filter { $0 != (versionPath(relative) as NSString).lastPathComponent }
            .compactMap { try? FileManager.default.attributesOfItem(atPath: versions + "/" + $0)[.size] as? Int }.reduce(0, +) ?? 0
        guard used + data.count <= Self.worktreeLimit else {
            files[relative]?.stopped = true
            return
        }
        try? FileManager.default.createDirectory(atPath: versions, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: versionPath(relative)), options: .atomic)
    }

    private func save() {
        try? FileManager.default.createDirectory(atPath: (file as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(files) { try? data.write(to: URL(fileURLWithPath: file), options: .atomic) }
        onChange?()
    }
}
