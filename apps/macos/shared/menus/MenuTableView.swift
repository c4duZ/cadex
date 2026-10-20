import AppKit

/// A table whose right click opens a PopupMenu instead of a system menu.
/// `menuRow` is the clicked row while the menu is open and while its
/// action runs (clickedRow no longer is by then), -1 otherwise.
@MainActor
public final class MenuTableView: NSTableView {
    /// The entries for a right click on `row` (-1: below the rows).
    public var contextEntries: ((_ row: Int) -> [MenuEntry])?
    public private(set) var menuRow = -1

    override public func menu(for event: NSEvent) -> NSMenu? {
        guard let contextEntries else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        menuRow = row
        PopupMenu.show(contextEntries(row), at: point, in: self) { [weak self] in self?.menuRow = -1 }
        return nil
    }
}
