import AppKit
import UILooks

/// The list of suggestions under the cursor while writing a link. A panel
/// that never takes the keyboard: the text view keeps typing, and the
/// session passes ↑ ↓ Enter Tab Esc to it.
@MainActor
final class CompletionPopup: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Item: Equatable {
        let title: String
        let detail: String
        /// What replaces the typed part.
        let insert: String
    }

    private let panel: NSPanel
    private let table = NSTableView()
    private(set) var items: [Item] = []
    var onChoose: ((Item) -> Void)?
    private static var rowHeight: CGFloat { UILooks.rowHeight(22) }
    private static var width: CGFloat { UILooks.pt(360) }

    override init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 6
        background.layer?.masksToBounds = true
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = table
        table.addTableColumn(NSTableColumn(identifier: .init("item")))
        table.headerView = nil
        table.rowHeight = Self.rowHeight
        table.backgroundColor = .clear
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)
        background.addSubview(scroll)
        scroll.frame = background.bounds.insetBy(dx: 0, dy: 3)
        scroll.autoresizingMask = [.width, .height]
        panel.contentView = background
    }

    var isVisible: Bool { panel.isVisible }

    /// Shows `list` under `caret` (screen coordinates), first row selected.
    func show(_ list: [Item], below caret: NSRect, in window: NSWindow) {
        items = list
        guard !list.isEmpty else { return hide() }
        table.reloadData()
        table.selectRowIndexes([0], byExtendingSelection: false)
        let height = CGFloat(min(list.count, 8)) * Self.rowHeight + 6
        panel.setFrame(NSRect(x: caret.minX, y: caret.minY - height - 2, width: Self.width, height: height), display: true)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func move(_ step: Int) {
        guard !items.isEmpty else { return }
        let row = min(max(table.selectedRow + step, 0), items.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func chooseSelected() {
        let row = table.selectedRow
        guard row >= 0, row < items.count else { return }
        onChoose?(items[row])
    }

    @objc private func clicked() { chooseSelected() }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: "")
        let item = items[row]
        let text = NSMutableAttributedString(string: item.title, attributes: [.font: UILooks.font(13)])
        if !item.detail.isEmpty {
            text.append(NSAttributedString(string: "  " + item.detail, attributes: [
                .font: UILooks.font(11), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        label.attributedStringValue = text
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }
}
