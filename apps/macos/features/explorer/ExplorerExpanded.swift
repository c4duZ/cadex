import AppKit

/// The open folders are remembered per root (docs/spec/explorer.md): opening
/// the app again, or coming back to that folder, opens the same ones, as
/// VS Code and CodeEdit do. Kept in the app's defaults, not in settings.json:
/// it is state, not a preference.
extension ExplorerController {
    static let expandedKey = "explorer.expandedFolders"
    /// Roots remembered at most; the oldest are dropped.
    static let rememberedRoots = 50

    func saveExpanded() {
        guard !restoringExpanded else { return }
        var all = UserDefaults.standard.dictionary(forKey: Self.expandedKey) as? [String: [String]] ?? [:]
        let open = (0..<outline.numberOfRows).compactMap { row -> String? in
            guard let node = outline.item(atRow: row) as? FileNode, outline.isItemExpanded(node) else { return nil }
            return node.path
        }
        all[root.path] = open.isEmpty ? nil : open
        if all.count > Self.rememberedRoots, let extra = all.keys.first(where: { $0 != root.path }) { all[extra] = nil }
        UserDefaults.standard.set(all, forKey: Self.expandedKey)
    }

    /// Opens the remembered folders of this root, parents first; the ones
    /// gone from the disk are skipped.
    func restoreExpanded() {
        let all = UserDefaults.standard.dictionary(forKey: Self.expandedKey) as? [String: [String]] ?? [:]
        guard let paths = all[root.path] else { return }
        restoringExpanded = true
        defer { restoringExpanded = false }
        for path in paths.sorted(by: { $0.count < $1.count }) { expand(path: path) }
    }

    /// Opens the folders down to `path`, and `path` itself.
    func expand(path: String) {
        var folder = root
        while let next = folder.children?.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
            guard next.isFolder else { return }
            loadChain(from: next)
            outline.expandItem(item(of: next))
            if next.path == path { return }
            folder = next
        }
    }
}
