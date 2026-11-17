import AppKit
import UILooks

/// The picker's drawing over the page: the outline and label of the element
/// under the mouse, the marked ones in green with their number, the banner
/// while picking, and the green or amber flash after sending. Native,
/// outside the DOM, so the page's CSS cannot hide or restyle it
/// (docs/adr/0018-element-picker.md). Clicks go through.
@MainActor
final class PickerOverlay: NSView {
    struct Mark: Equatable {
        var box: CGRect
        var label: String
    }

    /// The element under the mouse, in view points.
    var target: Mark? { didSet { if target != oldValue { needsDisplay = true } } }
    /// Marked with ⇧+click, labeled with their number.
    var selected: [Mark] = [] { didSet { if selected != oldValue { needsDisplay = true } } }
    var banner: String? { didSet { if banner != oldValue { needsDisplay = true } } }
    private var flash: (marks: [Mark], color: NSColor)?
    private var flashTimer: Timer?

    /// The PreviewOne mockup's picked element (components.preview.picked): the working blue
    /// outline and label; amber when it was only copied.
    static var pastedColor: NSColor { DesignTokens.Preview.Picked.Outline.color }
    static var selectedColor: NSColor { DesignTokens.Preview.Picked.Outline.color }
    static var copiedColor: NSColor { DesignTokens.Color.stateNeeds }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Shows where the picks went for a moment, after picking has ended.
    func flash(_ marks: [Mark], color: NSColor) {
        flash = (marks, color)
        needsDisplay = true
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flash = nil
                self?.needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let flash { flash.marks.forEach { draw($0, color: flash.color) } }
        selected.forEach { draw($0, color: Self.selectedColor) }
        // Over a marked one, its green stays and the outline adds nothing.
        if let target, flash == nil, !selected.contains(where: { $0.box == target.box }) { draw(target, color: Self.selectedColor) }
        if let banner { drawBanner(banner) }
    }

    /// The mockup's mark: a 2 pt outline 3 pt out from the element, no fill, and the label chip
    /// sitting on the outline's top edge.
    private func draw(_ mark: Mark, color: NSColor) {
        typealias P = DesignTokens.Preview.Picked
        let offset = UILooks.pt(P.outlineOffset), width = UILooks.pt(P.Outline.width)
        let box = mark.box.insetBy(dx: -offset, dy: -offset)
        color.setStroke()
        let corner = UILooks.pt(DesignTokens.Radius.control)
        let outline = NSBezierPath(roundedRect: box, xRadius: corner, yRadius: corner)
        outline.lineWidth = width
        outline.stroke()
        let text = NSAttributedString(string: mark.label, attributes: [
            .font: UILooks.font(P.Label.fontSize, weight: P.Label.weight), .foregroundColor: P.Label.color,
        ])
        let size = text.size()
        let pad = P.Label.padding
        var chip = CGRect(x: box.minX, y: box.minY - size.height - UILooks.pt(pad.top + pad.bottom),
                          width: size.width + UILooks.pt(pad.left + pad.right), height: size.height + UILooks.pt(pad.top + pad.bottom))
        // No room above: under the box, or inside it at the top.
        if chip.minY < 2 { chip.origin.y = box.maxY + 4 <= bounds.maxY - chip.height ? box.maxY + 4 : box.minY + 2 }
        chip.origin.x = max(2, min(chip.minX, bounds.maxX - chip.width - 2))
        color.setFill()
        let radius = UILooks.pt(P.Label.radius)
        NSBezierPath(roundedRect: chip, xRadius: radius, yRadius: radius).fill()
        text.draw(at: CGPoint(x: chip.minX + UILooks.pt(pad.left), y: chip.minY + UILooks.pt(pad.top)))
    }

    private func drawBanner(_ banner: String) {
        let text = NSAttributedString(string: banner, attributes: [
            .font: UILooks.font(12, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        let pill = CGRect(x: (bounds.width - size.width) / 2 - 14, y: 10, width: size.width + 28, height: size.height + 12)
        NSColor(white: 0.08, alpha: 0.88).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 14, y: pill.minY + 6))
    }
}
