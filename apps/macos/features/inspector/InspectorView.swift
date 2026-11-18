import AppKit
import Icons
import Menus
import Strings
import UILooks

/// The side column (docs/adr/0038-rail-and-side-column.md; docs/design/work-frame/screens.md, Rail):
/// left of the center, next to the rail. The pages' icons on top, the page, and at the foot the
/// scope row with the page's buttons (the right panel of docs/spec/inspector.md had the tabs' names
/// and the scope row on top).
/// The pages are features' views the app passes in; only the one showing is unhidden, so a page
/// that reads only while it shows (window and not hidden) reads only here and only then.
@MainActor
public final class InspectorView: NSView {
    typealias I = DesignTokens.Inspector
    /// Buttons shown in the scope row; the rest go under "⋯" (the sidebar's rule, 2026-10-22).
    static let maxShown = 3

    /// A tab came into view: the app makes or refreshes its content only then.
    public var onShow: ((String) -> Void)?
    /// The right edge dragged: the width asked, and whether the drag ended (the app saves it).
    public var onResize: ((CGFloat, Bool) -> Void)? {
        get { edge.onDrag }
        set { edge.onDrag = newValue }
    }
    private let edge = InspectorEdge()
    public private(set) var tab: String?
    private let tabs: [InspectorTab]
    private let run: (String) -> Void
    private let tabRow = NSStackView()
    private(set) var tabButtons: [InspectorTabButton] = []
    private let scopeRow = NSStackView()
    private let scopeLabel = NSTextField(labelWithString: "")
    private var scopeButtons: [InspectorIconButton] = []
    private let progress = NSProgressIndicator()
    private let content = NSView()
    private var scopes: [String: InspectorScope] = [:]
    private var busyTabs: Set<String> = []
    private var overflow: [InspectorAction] = []
    private let kbd = NSTextField(labelWithString: "")

    public init(tabs: [InspectorTab], shortcut: String?, run: @escaping (String) -> Void) {
        self.tabs = tabs
        self.run = run
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = I.bg.cgColor
        buildTabRow(shortcut: shortcut)
        buildScopeRow()
        let border = line(I.borderRight)
        let underTabs = line(I.IconTabs.borderBottom)
        let overFoot = line(I.Footer.borderTop)
        edge.currentWidth = { [weak self] in self?.bounds.width ?? 0 }
        for view in [tabRow, underTabs, content, overFoot, scopeRow, border, edge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        for tab in tabs { place(tab.view) }
        let hairline = DesignTokens.Stroke.hairline
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: hairline),
            // Under the tab row: the strip must not catch a click meant for a tab.
            edge.topAnchor.constraint(equalTo: underTabs.bottomAnchor),
            edge.bottomAnchor.constraint(equalTo: bottomAnchor),
            edge.trailingAnchor.constraint(equalTo: trailingAnchor),
            edge.widthAnchor.constraint(equalToConstant: InspectorEdge.grab),
            tabRow.topAnchor.constraint(equalTo: topAnchor),
            tabRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hairline),
            underTabs.topAnchor.constraint(equalTo: tabRow.bottomAnchor),
            underTabs.leadingAnchor.constraint(equalTo: leadingAnchor),
            underTabs.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hairline),
            underTabs.heightAnchor.constraint(equalToConstant: hairline),
            content.topAnchor.constraint(equalTo: underTabs.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hairline),
            content.bottomAnchor.constraint(equalTo: overFoot.topAnchor),
            overFoot.leadingAnchor.constraint(equalTo: leadingAnchor),
            overFoot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hairline),
            overFoot.heightAnchor.constraint(equalToConstant: hairline),
            overFoot.bottomAnchor.constraint(equalTo: scopeRow.topAnchor),
            scopeRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            scopeRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hairline),
            scopeRow.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("InspectorView is created in code") }

    override public var mouseDownCanMoveWindow: Bool { false }

    /// The ids of the tabs, in order.
    public var known: [String] { tabs.map(\.id) }

    /// Shows a tab (its command, a click, the saved inspector.tab); an unknown id shows nothing new.
    /// `announce` false only picks it (the panel closed at launch): no page is made or read.
    public func show(_ id: String, announce: Bool = true) {
        guard let shown = tabs.first(where: { $0.id == id }) else { return }
        tab = id
        for other in tabs { other.view.isHidden = other.id != id }
        for button in tabButtons { button.isOn = button.id == id }
        showScope(of: shown)
        if announce { onShow?(id) }
    }

    /// The tab row's shortcut, as the keymap says it now.
    public func setShortcut(_ label: String?) {
        kbd.stringValue = label ?? ""
    }

    /// The scope row's words for a tab; nil goes back to the tab's name.
    public func setScope(_ scope: InspectorScope?, for id: String) {
        scopes[id] = scope
        if tab == id, let shown = tabs.first(where: { $0.id == id }) { showScope(of: shown) }
    }

    /// A tab's action runs (a push): the scope row spins while that tab shows.
    public func setBusy(_ busy: Bool, for id: String) {
        if busy { busyTabs.insert(id) } else { busyTabs.remove(id) }
        updateBusy()
    }

    /// The pages' icons (components.inspector.iconTabs). The shortcut is no longer shown in the row:
    /// the column has no "⌥⌘I" label since it moved left (ADR 0038); setShortcut keeps the label for
    /// whoever asks.
    private func buildTabRow(shortcut: String?) {
        typealias Tabs = I.IconTabs
        tabRow.orientation = .horizontal
        tabRow.alignment = .centerY
        tabRow.spacing = UILooks.pt(Tabs.gap)
        tabRow.edgeInsets = NSEdgeInsets(top: UILooks.pt(Tabs.padding.top), left: UILooks.pt(Tabs.padding.left),
                                         bottom: UILooks.pt(Tabs.padding.bottom), right: UILooks.pt(Tabs.padding.right))
        tabButtons = tabs.map { tab in
            let button = InspectorTabButton(id: tab.id, title: tab.title, icon: tab.icon)
            button.onPress = { [weak self] in self?.run(tab.command) }
            return button
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        kbd.stringValue = shortcut ?? ""
        kbd.isHidden = true
        for view in tabButtons + [spacer] as [NSView] { tabRow.addArrangedSubview(view) }
    }

    private func buildScopeRow() {
        typealias S = I.Scope
        scopeRow.orientation = .horizontal
        // The words take the room left (the default gravity areas left it at the end, and the
        // buttons sat right after a short name: seen 2026-11-17).
        scopeRow.distribution = .fill
        scopeRow.spacing = UILooks.pt(S.gap)
        scopeRow.edgeInsets = NSEdgeInsets(top: UILooks.pt(S.padding.top), left: UILooks.pt(S.padding.left),
                                           bottom: UILooks.pt(S.padding.bottom), right: UILooks.pt(S.padding.right))
        scopeLabel.font = UILooks.font(S.fontSize)
        scopeLabel.textColor = S.color
        scopeLabel.lineBreakMode = .byTruncatingTail
        scopeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scopeLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        let press = NSClickGestureRecognizer(target: self, action: #selector(scopeClicked))
        scopeLabel.addGestureRecognizer(press)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        progress.setContentHuggingPriority(.required, for: .horizontal)
        scopeRow.addArrangedSubview(scopeLabel)
        scopeRow.addArrangedSubview(progress)
    }

    private func showScope(of shown: InspectorTab) {
        let scope = scopes[shown.id] ?? InspectorScope(shown.title)
        scopeLabel.stringValue = scope.text
        scopeLabel.toolTip = scope.tip
        typealias Scope = I.Scope
        scopeLabel.font = scope.strong ? UILooks.font(Scope.fontSize + 1, weight: .semibold) : UILooks.font(Scope.fontSize)
        scopeLabel.textColor = scope.strong ? DesignTokens.Color.textPrimary : Scope.color
        scopeButtons.forEach { $0.removeFromSuperview() }
        let first = shown.actions.prefix(Self.maxShown)
        overflow = Array(shown.actions.dropFirst(Self.maxShown)) + shown.more
        var buttons = first.map { action in
            let button = InspectorIconButton(command: action.command, icon: action.icon, tip: action.tip)
            button.onPress = { [weak self] in self?.run(action.command) }
            return button
        }
        if !overflow.isEmpty {
            let more = InspectorIconButton(command: "…", icon: .dotsThree, tip: T("More actions", "Mais ações"))
            more.onPress = { [weak self, weak more] in if let more { self?.showMore(below: more) } }
            buttons.append(more)
        }
        scopeButtons = buttons
        for button in buttons { scopeRow.addArrangedSubview(button) }
        updateBusy()
    }

    private func updateBusy() {
        tab.map(busyTabs.contains) == true ? progress.startAnimation(nil) : progress.stopAnimation(nil)
    }

    @objc private func scopeClicked() {
        guard let tab, let command = scopes[tab]?.command else { return }
        run(command)
    }

    private func showMore(below button: NSView) {
        PopupMenu.show(overflow.map { action in MenuEntry(action.tip, icon: action.icon) { [weak self] in self?.run(action.command) } },
                       below: button)
    }

    private func place(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        content.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: content.topAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func line(_ color: NSColor) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = color.cgColor
        return view
    }

    /// What the row shows, for tests.
    var tabTitles: [String] { tabButtons.map(\.title) }
    var scopeText: String { scopeLabel.stringValue }
    var scopeCommands: [String] { scopeButtons.map(\.command) }
}
