import AppKit
import UILooks
import Icons
import Menus
import Strings

/// The Git view of the sidebar (docs/spec/source-control.md): the lists of
/// changes, the commit message at the bottom, and a message for the states
/// without a repository. The branch and the sync buttons are in the
/// sidebar's header row, which the app fills from onBranch and onBusy.
@MainActor
final class SourceControlView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate {
    weak var controller: SourceControlController?
    let table = MenuTableView()
    private let scroll = NSScrollView()
    private let messageView = NSTextView()
    private let messageScroll = NSScrollView()
    private let commitButton = NSButton(title: "Commit", target: nil, action: nil)
    private let error = NSTextField(wrappingLabelWithString: "")
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let initButton = NSButton(title: T("Initialize Repository", "Inicializar repositório"), target: nil, action: nil)
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

    func show(error text: String?) {
        error.stringValue = text ?? ""
        error.isHidden = text == nil
    }

    /// Redraws from the controller's state.
    func render() {
        guard let controller else { return }
        let ready = controller.state == .ready || controller.state == .loading && controller.repo != nil
        [table, scroll, messageScroll, commitButton].forEach { $0.isHidden = !ready }
        empty.isHidden = ready
        initButton.isHidden = controller.state != .noRepository
        switch controller.state {
        case .gitMissing: empty.stringValue = T("Git was not found.\nInstall it with:\nxcode-select --install", "O git não foi encontrado.\nInstale com:\nxcode-select --install")
        case .noRepository: empty.stringValue = T("This folder is not a git repository.", "Esta pasta não é um repositório git.")
        case .loading where controller.repo == nil: empty.stringValue = T("Looking for the repository…", "Procurando o repositório…")
        default: empty.stringValue = ""
        }
        let s = controller.status
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
        table.addTableColumn(NSTableColumn(identifier: .init("change")))
        table.headerView = nil
        table.rowHeight = UILooks.rowHeight(22)
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

        messageView.font = UILooks.font(12)
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
        HoverTip.attach(T("Commit (⌘Enter in the message)", "Commit (⌘Enter na mensagem)"), to: commitButton)
        error.font = UILooks.font(11)
        error.textColor = .systemRed
        error.isHidden = true
        empty.alignment = .center
        empty.textColor = .secondaryLabelColor
        initButton.bezelStyle = .rounded
        initButton.target = self
        initButton.action = #selector(initPressed)

        for v in [scroll, messageScroll, commitButton, error, empty, initButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
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
