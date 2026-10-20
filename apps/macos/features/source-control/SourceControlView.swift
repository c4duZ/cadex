import AppKit
import Icons
import Menus

/// The Git view of the sidebar (docs/spec/source-control.md): branch and
/// sync buttons on top, the lists of changes, the commit message at the
/// bottom, and a message for the states without a repository.
@MainActor
final class SourceControlView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    weak var controller: SourceControlController?
    private let branch = NSButton(title: "", target: nil, action: nil)
    private let sync = NSTextField(labelWithString: "")
    private var buttons: [NSButton] = []
    private let progress = NSProgressIndicator()
    let table = MenuTableView()
    private let scroll = NSScrollView()
    private let messageView = NSTextView()
    private let messageScroll = NSScrollView()
    private let commitButton = NSButton(title: "Commit", target: nil, action: nil)
    private let error = NSTextField(wrappingLabelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let initButton = NSButton(title: "Inicializar repositório", target: nil, action: nil)
    private(set) var rows: [SourceControlRow] = []

    init() {
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SourceControlView is created in code") }

    var message: String { messageView.string }
    func messageForTests(_ text: String) { messageView.string = text }
    func clearMessage() { messageView.string = "" }

    func setBusy(_ busy: Bool) {
        busy ? progress.startAnimation(nil) : progress.stopAnimation(nil)
    }

    func show(error text: String?) {
        error.stringValue = text ?? ""
        error.isHidden = text == nil
    }

    /// Redraws from the controller's state.
    func render() {
        guard let controller else { return }
        let ready = controller.state == .ready || controller.state == .loading && controller.repo != nil
        [table, scroll, messageScroll, commitButton, branch, sync].forEach { $0.isHidden = !ready }
        buttons.forEach { $0.isHidden = !ready }
        empty.isHidden = ready
        initButton.isHidden = controller.state != .noRepository
        switch controller.state {
        case .gitMissing: empty.stringValue = "O git não foi encontrado.\nInstale com:\nxcode-select --install"
        case .noRepository: empty.stringValue = "Esta pasta não é um repositório git."
        case .loading where controller.repo == nil: empty.stringValue = "Procurando o repositório…"
        default: empty.stringValue = ""
        }
        let s = controller.status
        branch.title = s.detached ? "HEAD destacado em \(s.oid.prefix(7))" : s.branch
        var parts: [String] = []
        if s.ahead > 0 { parts.append("↑\(s.ahead)") }
        if s.behind > 0 { parts.append("↓\(s.behind)") }
        if s.upstream.isEmpty && !s.detached { parts.append("sem upstream") }
        sync.stringValue = parts.joined(separator: " ")
        rows = SourceControlRow.rows(for: s)
        table.reloadData()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        if case .header = rows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        SourceControlRowView(rows[row], controller: controller)
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .entry = rows[row] { return true }
        return false
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, case let .entry(entry, staged) = rows[table.selectedRow] else { return }
        controller?.openDiff(entry, staged: staged)
    }

    /// The entries the context menu acts on: the clicked row, or the selection.
    func selectedEntries() -> [(GitRepository.Entry, Bool)] {
        let clicked = table.menuRow
        let indexes = clicked >= 0 && !table.selectedRowIndexes.contains(clicked) ? IndexSet(integer: clicked) : table.selectedRowIndexes
        return indexes.compactMap { i in
            if case let .entry(e, staged) = rows[i] { return (e, staged) }
            return nil
        }
    }

    // MARK: Message (⌘Enter commits)

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            _ = controller?.run("git.commit")
            return true
        }
        return false
    }

    // MARK: Layout

    private func build() {
        branch.isBordered = false
        branch.image = Icon.gitBranch.image(size: 13)
        branch.imagePosition = .imageLeading
        branch.font = .systemFont(ofSize: 12, weight: .semibold)
        branch.target = self
        branch.action = #selector(runButton(_:))
        branch.identifier = .init("git.switch-branch")
        branch.lineBreakMode = .byTruncatingTail
        sync.font = .systemFont(ofSize: 11)
        sync.textColor = .secondaryLabelColor
        buttons = [("git.fetch", Icon.arrowsClockwise, "Fetch"), ("git.pull", Icon.arrowDown, "Pull"), ("git.push", Icon.arrowUp, "Push")].map { id, icon, tip in
            let b = NSButton(image: icon.image(size: 13), target: self, action: #selector(runButton(_:)))
            b.isBordered = false
            HoverTip.attach(tip, to: b)
            b.identifier = .init(id)
            b.contentTintColor = .secondaryLabelColor
            return b
        }
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        let top = NSStackView(views: [branch, sync, NSView(), progress] + buttons)
        top.spacing = 4
        top.setHuggingPriority(.defaultLow, for: .horizontal)
        branch.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        table.addTableColumn(NSTableColumn(identifier: .init("change")))
        table.headerView = nil
        table.rowHeight = 22
        table.style = .plain
        table.backgroundColor = .clear
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.contextEntries = { [weak self] _ in self.map(SourceControlMenu.entries) ?? [] }
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        messageView.font = .systemFont(ofSize: 12)
        messageView.isRichText = false
        messageView.delegate = self
        messageView.textContainerInset = NSSize(width: 4, height: 4)
        messageScroll.documentView = messageView
        messageScroll.hasVerticalScroller = true
        messageScroll.borderType = .lineBorder
        messageView.autoresizingMask = [.width]
        commitButton.bezelStyle = .rounded
        commitButton.target = self
        commitButton.action = #selector(runButton(_:))
        commitButton.identifier = .init("git.commit")
        HoverTip.attach("Commit (⌘Enter na mensagem)", to: commitButton)
        error.font = .systemFont(ofSize: 11)
        error.textColor = .systemRed
        error.isHidden = true
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        initButton.bezelStyle = .rounded
        initButton.target = self
        initButton.action = #selector(initPressed)

        for v in [top, scroll, messageScroll, commitButton, error, empty, initButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            top.heightAnchor.constraint(equalToConstant: 24),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageScroll.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            messageScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            messageScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            messageScroll.heightAnchor.constraint(equalToConstant: 64),
            commitButton.topAnchor.constraint(equalTo: messageScroll.bottomAnchor, constant: 6),
            commitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            error.topAnchor.constraint(equalTo: commitButton.bottomAnchor, constant: 4),
            error.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            error.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            error.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            empty.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            empty.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            empty.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            initButton.topAnchor.constraint(equalTo: empty.bottomAnchor, constant: 10),
            initButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    @objc private func runButton(_ sender: NSButton) {
        _ = controller?.run(sender.identifier?.rawValue ?? "")
    }

    @objc private func initPressed() {
        controller?.initRepository()
    }
}
