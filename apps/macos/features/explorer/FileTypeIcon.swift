import AppKit
import Icons
import UILooks

/// The icon of a tree row: folders open or closed, links, and files by
/// their name (FileIcons, shared with the tabs), in the Files drawing's
/// colors (components.inspector.tree.iconColor).
enum FileTypeIcon {
    static func icon(name: String, entry: FileEntry?, expanded: Bool) -> Icon {
        guard let entry else { return expanded ? .folderOpen : .folder }
        if entry.opensAsFolder { return expanded ? .folderOpen : .folder }
        if entry.kind == .symlink { return .link }
        return FileIcons.icon(forFileNamed: name)
    }

    typealias Colors = DesignTokens.Inspector.Tree.IconColor

    static func color(name: String, entry: FileEntry?) -> NSColor {
        guard let entry, !entry.opensAsFolder else { return Colors.folder }
        let ext = (name as NSString).pathExtension.lowercased()
        if docs.contains(ext) { return Colors.doc }
        return sources.contains(ext) ? Colors.code : Colors.other
    }

    private static let docs: Set<String> = ["md", "markdown", "mdx", "txt", "rst", "adoc", "pdf"]
    private static let sources: Set<String> = [
        "swift", "zig", "rs", "c", "h", "cc", "cpp", "hpp", "m", "mm", "go", "py", "rb", "js", "jsx", "mjs", "cjs",
        "ts", "tsx", "java", "kt", "cs", "php", "lua", "sh", "zsh", "bash", "fish", "sql", "html", "css", "scss",
        "vue", "svelte", "dart", "ex", "exs", "erl", "hs", "ml", "scala", "clj", "nim", "jl", "r",
    ]
}
