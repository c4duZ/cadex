import AppKit
import Icons

/// The icon of a tree row: folders open or closed, links, and files by
/// their name (FileIcons, shared with the tabs).
enum FileTypeIcon {
    static func icon(name: String, entry: FileEntry?, expanded: Bool) -> Icon {
        guard let entry else { return expanded ? .folderOpen : .folder }
        if entry.opensAsFolder { return expanded ? .folderOpen : .folder }
        if entry.kind == .symlink { return .link }
        return FileIcons.icon(forFileNamed: name)
    }
}
