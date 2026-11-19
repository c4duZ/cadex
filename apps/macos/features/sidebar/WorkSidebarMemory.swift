import AppKit
import Strings
import UILooks

/// The sidebar with the Memória page open (plan 40 C; MemorySidebar.dc.html; the owner,
/// 2026-11-19: one sidebar, no second column): the queue stays on top, "‹ Trabalho" takes the
/// switch's place, the panel's sections (the app gives them, `setMemory`) take the list's, and
/// Memória is lit in the foot with upstream's version beside it.
extension WorkSidebarView {
    /// The sections' view, held for the Memory mode.
    public func setMemory(_ view: NSView) {
        memoryHost?.removeFromSuperview()
        memoryHost = view
        view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor),
        ])
        view.isHidden = mode != .memory
    }

    /// "ai-memory 3.5.0", at the right of the lit Memória row.
    public func setMemoryVersion(_ text: String) { memoryFoot?.setDetail(text) }

    /// In or out of the Memory mode: the parts it swaps.
    func showMemoryParts(_ on: Bool) {
        backRow.isHidden = !on
        switchRow.isHidden = on || recentsShown != nil
        memoryHost?.isHidden = !on
        memoryFoot?.lit = on
        guard on else {
            // Nothing open: the recents' list comes back, not a view of a place.
            if recentsShown != nil { setFilesHidden(true) }
            return
        }
        scroll.isHidden = true
        files?.isHidden = true
        edge.isHidden = true
    }

    /// Esc in the sidebar, with the sections shown: back to Work (MemorySidebar, "‹ Trabalho").
    override public func cancelOperation(_ sender: Any?) {
        guard mode == .memory else { return super.cancelOperation(sender) }
        run("sidebar.show-work")
    }

    /// For tests.
    var memoryShown: Bool { mode == .memory && memoryHost?.isHidden == false && !backRow.isHidden && switchRow.isHidden }
    var memoryFootLit: Bool { memoryFoot?.lit == true }
    var memoryFootDetail: String { memoryFoot?.detailSaid ?? "" }
    func pressBack() { backRow.onPress?() }
    func pressMemoryFoot() { memoryFoot?.onPress?() }
}

/// "‹ Trabalho" (components.memoryPanel.nav.back): back to the Work view; the center keeps the page.
@MainActor
final class WorkBackRow: NSView {
    typealias B = DesignTokens.MemoryPanel.Nav.Back
    var onPress: (() -> Void)?
    private var hovering = false {
        didSet { layer?.backgroundColor = hovering ? DesignTokens.WorkSidebar.Row.Selected.bg.cgColor : nil }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(B.radius)
        let label = NSTextField(labelWithString: "‹ " + T("Work", "Trabalho"))
        label.font = UILooks.font(B.fontSize, weight: B.weight)
        label.textColor = B.color
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: UILooks.rowHeight(B.height)),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(B.padding.left)),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(T("Back to Work", "Voltar ao Trabalho"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("WorkBackRow is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }
    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
