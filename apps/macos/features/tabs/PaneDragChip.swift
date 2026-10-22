import AppKit
import UILooks

/// The small label under the pointer while a pane is dragged by its header:
/// the pane's icon and name, so you see what you carry while the panes
/// themselves move into place (the owner found cards over the panes and a
/// blue drop area crude, 2026-10-22).
@MainActor
final class PaneDragChip: NSView {
    init(info: PaneHeaderView.Info, style: TabBarView.Style) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(7)
        layer?.backgroundColor = style.activeFill.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
        shadow = NSShadow()
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        let icon = NSImageView(image: info.image ?? info.icon.image(size: UILooks.pt(13)))
        icon.contentTintColor = info.image == nil ? info.iconColor ?? style.text : nil
        let label = NSTextField(labelWithString: info.title)
        label.font = UILooks.font(12, weight: .medium)
        label.textColor = style.text
        label.lineBreakMode = .byTruncatingMiddle
        let row = NSStackView(views: [icon, label])
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(10), bottom: 0, right: UILooks.pt(12))
        row.frame.size = row.fittingSize
        let size = CGSize(width: min(row.fittingSize.width, UILooks.pt(240)), height: UILooks.pt(28))
        frame.size = size
        row.frame = CGRect(origin: .zero, size: size)
        addSubview(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneDragChip is created in code") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Just below and right of the pointer, kept inside `bounds`.
    func follow(_ pointer: CGPoint, in bounds: CGRect) {
        let x = min(max(pointer.x + 12, 4), bounds.width - frame.width - 4)
        let y = min(max(pointer.y + 14, 4), bounds.height - frame.height - 4)
        setFrameOrigin(CGPoint(x: x, y: y))
    }
}
