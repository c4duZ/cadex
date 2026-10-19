import AppKit

/// The window's content: the tab bar on top and the active tab below.
/// Only the active tab is in the view hierarchy, so hidden tabs do not draw
/// (docs/spec/tabs.md); their sessions keep reading output.
public final class TabsView: NSView {
    let bar = TabBarView()
    private(set) weak var content: NSView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bar)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: topAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: TabBarView.height),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TabsView is created in code") }

    func show(_ view: NSView) {
        guard view !== content else { return }
        content?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: bar.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        content = view
        // A tab coming back into view draws what arrived while it was hidden.
        view.needsDisplay = true
    }
}
