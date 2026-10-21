import AppKit
import UILooks

/// The little arrow that opens and closes a part of the Agents page (a
/// session's subagents, a project's sessions): drawn as a stroke so it
/// turns 90° in 0.18 s instead of swapping pictures. It takes its own
/// clicks, so the row under it keeps its own (the owner, 2026-10-21: one
/// click went to the terminal or opened the list, never both).
@MainActor
final class AgentCaret: NSView {
    var onClick: (() -> Void)?
    private let shape = CAShapeLayer()
    private(set) var open: Bool

    init(open: Bool, color: NSColor, size: CGFloat = UILooks.pt(16)) {
        self.open = open
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        let arm = size * 0.16
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -arm * 0.6, y: arm))
        path.addLine(to: CGPoint(x: arm * 0.6, y: 0))
        path.addLine(to: CGPoint(x: -arm * 0.6, y: -arm))
        shape.path = path
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = 1.4
        shape.lineCap = .round
        shape.lineJoin = .round
        shape.bounds = CGRect(x: -size / 2, y: -size / 2, width: size, height: size)
        shape.position = CGPoint(x: size / 2, y: size / 2)
        shape.transform = Self.turn(open)
        layer?.addSublayer(shape)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)])
        setAccessibilityElement(true)
        setAccessibilityRole(.disclosureTriangle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentCaret is created in code") }

    /// Pointing down when open; y grows upwards in the layer, so -90°.
    private static func turn(_ open: Bool) -> CATransform3D {
        CATransform3DMakeRotation(open ? -.pi / 2 : 0, 0, 0, 1)
    }

    func turn(to open: Bool) {
        guard open != self.open else { return }
        self.open = open
        let spin = CABasicAnimation(keyPath: "transform")
        spin.fromValue = shape.presentation()?.transform ?? shape.transform
        spin.duration = 0.18
        spin.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shape.add(spin, forKey: "turn")
        shape.transform = Self.turn(open)
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.insetBy(dx: -4, dy: -4).contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

/// A part of the page that unfolds and folds: its height and opacity move
/// together in 0.2 s, ease out going in and faster coming out, where it
/// used to appear at once and the page seemed to freeze (the owner,
/// 2026-10-21). Only height and alpha move, nothing else lays out again.
@MainActor
final class AgentReveal: NSView {
    private let stack = NSStackView()
    private var height: NSLayoutConstraint?

    init(_ views: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomAnchor.constraint(equalTo: stack.bottomAnchor).withPriority(.defaultHigh),
        ])
        for view in views {
            stack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentReveal is created in code") }

    /// From folded to its full height, once it is in the page.
    func unfold() {
        let pin = heightAnchor.constraint(equalToConstant: 0)
        pin.isActive = true
        height = pin
        alphaValue = 0
        superview?.layoutSubtreeIfNeeded()
        let full = stack.fittingSize.height
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            pin.animator().constant = full
            animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.height?.isActive = false
                self?.height = nil
            }
        })
    }

    /// To nothing, then `done` (which draws the page without it).
    func fold(then done: @escaping @MainActor () -> Void) {
        let pin = heightAnchor.constraint(equalToConstant: bounds.height)
        pin.isActive = true
        height = pin
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            pin.animator().constant = 0
            animator().alphaValue = 0
        }, completionHandler: { MainActor.assumeIsolated { done() } })
    }
}

extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
