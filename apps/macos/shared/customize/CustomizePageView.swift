import AppKit
import UILooks

/// A Customize list inside another view (the settings window's Status Bar and Accounts sections,
/// plan 32 B): the page's rows to drag and switch, each change to its owner at once. Its height is
/// its rows'.
@MainActor
public final class CustomizePageView: NSView {
    private let list = CustomizeList()
    private var page: CustomizePage

    public init(_ page: CustomizePage, colors: CustomizeColors = .frame) {
        self.page = page
        super.init(frame: .zero)
        list.translatesAutoresizingMaskIntoConstraints = false
        addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: leadingAnchor), list.trailingAnchor.constraint(equalTo: trailingAnchor),
            list.topAnchor.constraint(equalTo: topAnchor), list.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        list.onChange = { [weak self] entries in self?.page.onChange(entries) }
        list.show(page.entries, colors: colors)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("CustomizePageView is created in code") }

    public override var isFlipped: Bool { true }

    /// What it shows now (the tests read it).
    public var entries: [CustomizeEntry] { list.entries }

    /// The settings changed elsewhere (⌘K, another window): the rows show them.
    public func refresh(_ page: CustomizePage) {
        self.page = page
        if list.entries != page.entries { list.show(page.entries, colors: .frame) }
    }
}
