import AppKit

/// The active tab's panes. Only the active tab is in the view hierarchy, so
/// hidden tabs do not draw (docs/spec/tabs.md); their sessions keep reading
/// output. The tab bar lives in the window's title bar (TabsController.bar).
public final class TabsView: NSView {
    private(set) weak var content: NSView?

    func show(_ view: NSView) {
        guard view !== content else { return }
        content?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        content = view
        // A tab coming back into view draws what arrived while it was hidden.
        view.needsDisplay = true
    }
}
