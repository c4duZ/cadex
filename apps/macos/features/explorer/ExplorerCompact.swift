import AppKit

/// Compact folders, as in VS Code (docs/spec/explorer.md, "Aparência"): a
/// folder whose only visible item is another folder shares its row with it,
/// "src/main/java". The row's item is the first folder (the head); it shows
/// the children of the last one (the tail), and actions act on the tail.
/// Only loaded folders compact, so the chain is read when the row opens.
extension ExplorerController {
    /// The head, then each folder that is the only item of the one before.
    func chain(from head: FileNode) -> [FileNode] {
        var nodes = [head]
        while let only = onlyFolder(in: nodes[nodes.count - 1], loadedOnly: true) { nodes.append(only) }
        return nodes
    }

    func tail(of head: FileNode) -> FileNode {
        chain(from: head).last ?? head
    }

    /// The row's item for any node: the head of the chain it belongs to.
    func item(of node: FileNode) -> FileNode {
        compactHeads[node.path] ?? node
    }

    func row(of node: FileNode) -> Int {
        outline.row(forItem: item(of: node))
    }

    /// The folder that holds `node`, found by path: a chain's tail is not an
    /// item of the outline, so the outline cannot say.
    func parentFolder(of node: FileNode) -> FileNode {
        root.find((node.path as NSString).deletingLastPathComponent) ?? root
    }

    /// The text of a row: the chain's names joined by "/".
    func title(of head: FileNode) -> String {
        chain(from: head).map(\.name).joined(separator: "/")
    }

    /// Remembers which head shows each folder of its chain.
    func register(_ head: FileNode) {
        for node in chain(from: head) { compactHeads[node.path] = head }
    }

    /// Opening a row reads the folders down the chain, so it can compact.
    func loadChain(from head: FileNode) {
        var node = head
        if !node.isLoaded { node.load() }
        while let only = onlyFolder(in: node, loadedOnly: false) {
            if !only.isLoaded { only.load() }
            node = only
        }
    }

    /// The single visible item of `folder`, when it is a folder (not a link:
    /// a link stays a row of its own, so it can be renamed or removed).
    private func onlyFolder(in folder: FileNode, loadedOnly: Bool) -> FileNode? {
        guard folder !== root, folder.isFolder, folder.isLoaded else { return nil }
        let shown = folder.visibleChildren(showHidden: showHidden)
        guard shown.count == 1, let only = shown.first, !only.isNote, only.isFolder,
              only.entry?.kind != .symlink, !loadedOnly || only.isLoaded else { return nil }
        return only
    }
}
