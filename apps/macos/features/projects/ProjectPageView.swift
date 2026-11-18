import AppKit
import Strings
import Tabs
import UILooks

/// What a project's page asks the app to do.
@MainActor
public struct ProjectPageActions {
    public var race: () -> Void = {}
    public var newTask: () -> Void = {}
    public var openConversation: (String) -> Void = { _ in }
    public var toggleAutomation: (String) -> Void = { _ in }
    public var newTaskShortcut: () -> String? = { nil }
    /// Gathers the page's state (off the main thread where it reads git or files) and gives it.
    public var load: (@escaping @MainActor (ProjectPageState) -> Void) -> Void = { _ in }

    public init() {}
}

/// A project's page in the center (plan 30 A, done with plan 29's review; the Project mockup):
/// the name and where it is, Race… and New task, four numbers, the recent conversations, the
/// automations with their switch and the accounts used here. A tab whose identity is the
/// project's (`ProjectPageDocument.identity(for:)`), read again each time it shows.
@MainActor
public final class ProjectPageDocument: TabDocument {
    public static func identity(for folder: String) -> String { "project:" + folder }

    public let folder: String
    private let actions: ProjectPageActions
    private let page = FlippedPage()
    public var view: NSView { page }
    public var title: String { T("Overview", "Visão geral") }
    public var identity: String { Self.identity(for: folder) }
    public var hasUnsavedChanges: Bool { false }
    public var onChange: (() -> Void)?
    public var isPage: Bool { true }

    public init(folder: String, actions: ProjectPageActions) {
        self.folder = folder
        self.actions = actions
        page.wantsLayer = true
        page.layer?.backgroundColor = DesignTokens.Color.bgWindow.cgColor
        reload()
    }

    public func focus() { reload() }
    public func confirmClose(in window: NSWindow?, then close: @escaping @MainActor () -> Void) { close() }
    public func close() {}

    /// Reads again (the tab shows, an automation turned on or off).
    public func reload() {
        actions.load { [weak self] state in self?.show(state) }
    }

    func show(_ state: ProjectPageState) {
        page.show(head: head(state), stats: stats(state), columns: columns(state))
    }

    private func head(_ state: ProjectPageState) -> NSView {
        typealias H = PP.Head
        let words = vertical([pageLabel(state.name, size: PP.Title.fontSize, color: DesignTokens.Color.textPrimary, weight: PP.Title.weight,
                                        tracking: PP.Title.tracking),
                              pageLabel(state.place, size: DesignTokens.FontSize.body, color: H.meta)], gap: H.titleGap)
        words.setContentHuggingPriority(.init(1), for: .horizontal)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let race = DesignButton.make(T("Race…", "Corrida…"), .secondary) { [weak self] in self?.actions.race() }
        let shortcut = actions.newTaskShortcut().map { "  " + $0 } ?? ""
        let task = DesignButton.make(T("New task", "Nova tarefa") + shortcut, .primary) { [weak self] in self?.actions.newTask() }
        let buttons = NSStackView(views: [race, task])
        buttons.spacing = UILooks.pt(H.gap)
        let row = NSStackView(views: [words, buttons])
        row.alignment = .bottom
        row.spacing = UILooks.pt(H.gap)
        page.head = row
        return row
    }

    /// The four numbers: four columns, two on a narrow page, one on a very narrow one.
    private func stats(_ state: ProjectPageState) -> NSView {
        let minimum = UILooks.pt(PP.Stat.minWidth)
        return PageFlow(state.stats.map(statCard), mode: .grid { width in width >= minimum * 4 ? 4 : width >= minimum * 2 ? 2 : 1 },
                        gap: PP.Stat.gridGap)
    }

    private func columns(_ state: ProjectPageState) -> (left: NSView, right: NSView) {
        typealias C = PP.Columns
        let talks = state.conversations.map { talk -> NSView in
            let row = pageRow(state: talk.state, title: talk.title, meta: talk.detail,
                              tail: pageLabel(talk.when, size: PP.Row.When.fontSize, color: PP.Row.When.color))
            row.onPress = { [weak self] in self?.actions.openConversation(talk.id) }
            return row
        }
        var leftViews: [NSView] = [sectionLabel(T("RECENT CONVERSATIONS", "CONVERSAS RECENTES"))] + talks
        if talks.isEmpty { leftViews.append(pageLabel(T("No conversation here yet", "Nenhuma conversa aqui ainda"), size: PP.Row.Meta.fontSize, color: PP.Row.Meta.color)) }
        let left = vertical(leftViews, gap: C.listGap)
        let jobs = state.automations.map { job -> NSView in
            let toggle = PageSwitch(on: job.on)
            toggle.onPress = { [weak self] in self?.actions.toggleAutomation(job.id) }
            return pageRow(state: nil, title: job.name, meta: job.detail, tail: toggle)
        }
        var right: [NSView] = [sectionLabel(T("AUTOMATIONS", "AUTOMAÇÕES"))] + jobs
        if jobs.isEmpty { right.append(pageLabel(T("None in this project", "Nenhuma neste projeto"), size: PP.Row.Meta.fontSize, color: PP.Row.Meta.color)) }
        let chips = PageFlow(state.accounts.map(accountChip), mode: .wrap, gap: PP.Account.gap)
        right += [sectionLabel(T("ACCOUNTS USED HERE", "CONTAS USADAS AQUI")), chips]
        let rightStack = vertical(right, gap: C.listGap)
        rightStack.setCustomSpacing(UILooks.pt(C.listGap + PP.Label.marginTop), after: right[right.count - 3])
        for view in talks + leftViews.suffix(1) { view.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true }
        for view in jobs + [chips] { view.widthAnchor.constraint(equalTo: rightStack.widthAnchor).isActive = true }
        return (left, rightStack)
    }
}

/// The page's own view: a scroll view whose document is laid top-down at the page's width; the
/// two columns sit side by side on a wide page and one under the other on a narrow one
/// (components.project.columns.stackBelow).
@MainActor
final class FlippedPage: NSView {
    private let scroll = NSScrollView()
    private let content = FlippedContent()
    private let column = NSStackView()
    private let pair = NSStackView()
    private var ratio: NSLayoutConstraint?
    private var stacked: [NSLayoutConstraint] = []
    /// The name and the buttons: side by side, or the buttons under the name on a narrow page.
    weak var head: NSStackView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        content.translatesAutoresizingMaskIntoConstraints = false
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(PP.gap)
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        pair.alignment = .top
        pair.spacing = UILooks.pt(PP.Columns.gap)
        let pad = PP.padding
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UILooks.pt(pad.left)),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UILooks.pt(pad.right)),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: UILooks.pt(pad.top)),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -UILooks.pt(pad.bottom)),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FlippedPage is created in code") }

    override var isFlipped: Bool { true }

    func show(head: NSView, stats: NSView, columns: (left: NSView, right: NSView)) {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pair.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pair.addArrangedSubview(columns.left)
        pair.addArrangedSubview(columns.right)
        for view in [head, stats, pair] {
            column.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        ratio = columns.right.widthAnchor.constraint(equalTo: columns.left.widthAnchor, multiplier: PP.Columns.right / PP.Columns.left)
        stacked = [columns.left.widthAnchor.constraint(equalTo: pair.widthAnchor), columns.right.widthAnchor.constraint(equalTo: pair.widthAnchor)]
        arrange(force: true)
    }

    override func layout() {
        super.layout()
        arrange(force: false)
    }

    /// Side by side from components.project.columns.stackBelow up, else one under the other.
    private func arrange(force: Bool) {
        let narrow = bounds.width - UILooks.pt(PP.padding.left + PP.padding.right) < UILooks.pt(PP.Columns.stackBelow)
        let wanted: NSUserInterfaceLayoutOrientation = narrow ? .vertical : .horizontal
        guard force || pair.orientation != wanted else { return }
        head?.orientation = wanted
        head?.alignment = narrow ? .leading : .bottom
        pair.orientation = wanted
        pair.alignment = narrow ? .leading : .top
        pair.spacing = UILooks.pt(narrow ? PP.gap : PP.Columns.gap)
        ratio?.isActive = !narrow
        stacked.forEach { $0.isActive = narrow }
    }
}

/// The scroll view's document: top-down.
final class FlippedContent: NSView {
    override var isFlipped: Bool { true }
}
