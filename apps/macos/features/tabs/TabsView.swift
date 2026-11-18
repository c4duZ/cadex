import AppKit

/// The active tab's panes. Only the active tab is in the view hierarchy, so
/// hidden tabs do not draw (docs/spec/tabs.md); their sessions keep reading
/// output. The tab bar lives in the window's title bar (TabsController.bar).
public final class TabsView: NSView {
    private(set) weak var content: NSView?

    private weak var banner: NSView?

    /// The tab's panes, under its banner when it has one.
    func show(_ view: NSView, banner: NSView? = nil) {
        guard view !== content || banner !== self.banner else { return }
        content?.removeFromSuperview()
        self.banner?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        var top = topAnchor
        if let banner {
            banner.translatesAutoresizingMaskIntoConstraints = false
            addSubview(banner)
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: topAnchor),
                banner.leadingAnchor.constraint(equalTo: leadingAnchor),
                banner.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            top = banner.bottomAnchor
        }
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: top),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        content = view
        self.banner = banner
        // A tab coming back into view draws what arrived while it was hidden.
        view.needsDisplay = true
    }
}
