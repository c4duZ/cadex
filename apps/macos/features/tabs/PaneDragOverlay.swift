import AppKit
import UILooks

/// What shows while a pane is dragged by its header: a card per pane with
/// its name, the others gliding to where they will be (0.2 s, as the
/// sidebar's icons move while one is dragged), the place the dragged pane
/// will take outlined in the accent, and the dragged card under the
/// pointer (the owner, 2026-10-22). Cards and not the panes themselves: a
/// terminal resized at every step would send its shell a resize each time.
@MainActor
final class PaneDragOverlay: NSView {
    struct Card {
        let id: Int
        let title: String
    }

    private var cards: [Int: CALayer] = [:]
    private let slot = CALayer()
    private let ghost = CALayer()
    private let dragged: Int
    private let style: TabBarView.Style

    init(frame: NSRect, cards list: [Card], frames: [Int: CGRect], dragged: Int, style: TabBarView.Style) {
        self.dragged = dragged
        self.style = style
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        // The dragged pane is the card under the pointer and its slot, not
        // a card left where it was.
        for card in list where card.id != dragged {
            let layer = makeCard(card.title)
            layer.frame = frames[card.id] ?? .zero
            self.layer?.addSublayer(layer)
            cards[card.id] = layer
        }
        slot.borderColor = style.accent.cgColor
        slot.borderWidth = 2
        slot.cornerRadius = 8
        slot.backgroundColor = style.accent.withAlphaComponent(0.12).cgColor
        slot.isHidden = true
        layer?.addSublayer(slot)
        let title = list.first { $0.id == dragged }?.title ?? ""
        ghost.addSublayer(text(title))
        styleCard(ghost)
        ghost.opacity = 0.92
        ghost.shadowOpacity = 0.4
        ghost.shadowRadius = 12
        ghost.shadowOffset = CGSize(width: 0, height: -4)
        layer?.addSublayer(ghost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PaneDragOverlay is created in code") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The cards glide to `frames`; the dragged pane's frame is the slot.
    func show(_ frames: [Int: CGRect], pointer: CGPoint) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        for (id, layer) in cards where id != dragged {
            if let frame = frames[id] { layer.frame = frame.insetBy(dx: 3, dy: 3) }
        }
        if let target = frames[dragged] {
            slot.isHidden = false
            slot.frame = target.insetBy(dx: 3, dy: 3)
        }
        CATransaction.commit()
        // The card under the pointer follows it at once.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let size = CGSize(width: UILooks.pt(200), height: UILooks.pt(64))
        // Kept inside: at an edge, half of it went off and hid its name.
        let x = min(max(pointer.x - size.width / 2, 4), bounds.width - size.width - 4)
        let y = min(max(pointer.y - UILooks.pt(12), 4), bounds.height - size.height - 4)
        ghost.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        ghost.sublayers?.first?.frame = ghost.bounds.insetBy(dx: 12, dy: 10)
        CATransaction.commit()
    }

    private func makeCard(_ title: String) -> CALayer {
        let card = CALayer()
        styleCard(card)
        let label = text(title)
        card.addSublayer(label)
        card.layoutManager = nil
        label.frame = CGRect(x: 12, y: 10, width: 400, height: 18)
        return card
    }

    private func styleCard(_ card: CALayer) {
        card.backgroundColor = style.activeFill.cgColor
        card.borderColor = NSColor.separatorColor.cgColor
        card.borderWidth = 1
        card.cornerRadius = 8
    }

    private func text(_ string: String) -> CATextLayer {
        let label = CATextLayer()
        label.string = string
        label.font = UILooks.font(12, weight: .medium)
        label.fontSize = UILooks.pt(12)
        label.foregroundColor = style.text.cgColor
        label.truncationMode = .end
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        return label
    }
}
