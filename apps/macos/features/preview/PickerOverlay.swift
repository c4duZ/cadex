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

    static let pastedColor = NSColor.systemGreen
    static let selectedColor = NSColor.systemGreen
    static let copiedColor = NSColor.systemOrange

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
        if let target, flash == nil, !selected.contains(where: { $0.box == target.box }) { draw(target, color: .controlAccentColor) }
        if let banner { drawBanner(banner) }
    }

    private func draw(_ mark: Mark, color: NSColor) {
        let box = mark.box.insetBy(dx: -1, dy: -1)
        color.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: box).fill()
        color.setStroke()
        let outline = NSBezierPath(rect: box.insetBy(dx: 1, dy: 1))
        outline.lineWidth = 2
        outline.stroke()
        let text = NSAttributedString(string: mark.label, attributes: [
            .font: UILooks.monospaced(11, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let size = text.size()
        var chip = CGRect(x: box.minX, y: box.minY - size.height - 8, width: size.width + 10, height: size.height + 4)
        // No room above: under the box, or inside it at the top.
        if chip.minY < 2 { chip.origin.y = box.maxY + 4 <= bounds.maxY - chip.height ? box.maxY + 4 : box.minY + 2 }
        chip.origin.x = max(2, min(chip.minX, bounds.maxX - chip.width - 2))
        color.setFill()
        NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
        text.draw(at: CGPoint(x: chip.minX + 5, y: chip.minY + 2))
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
