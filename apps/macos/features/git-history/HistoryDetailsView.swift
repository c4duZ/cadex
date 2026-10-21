import AppKit
import UILooks
import Strings

/// The selected commit (docs/spec/git-history.md): the whole message,
/// author, date and parents on the left; its files with the kind of change
/// and +/− lines on the right. Clicking a file opens its diff.
@MainActor
final class HistoryDetailsView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onOpenFile: ((CommitDetails.File) -> Void)?
    private let info = NSTextView()
    private let infoScroll = NSScrollView()
    let files = NSTableView()
    private let filesScroll = NSScrollView()
    private(set) var shownFiles: [CommitDetails.File] = []

    private let columns = NSStackView()

    /// The sidebar: the message above the files, not side by side (two
    /// columns of 120 points showed neither).
    func setCompact(_ compact: Bool) {
        columns.orientation = compact ? .vertical : .horizontal
    }

    init() {
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("HistoryDetailsView is created in code") }

    func show(_ commit: HistoryCommit?, details: CommitDetails?) {
        shownFiles = details?.files ?? []
        files.reloadData()
        info.textStorage?.setAttributedString(Self.text(commit, details: details))
    }

    static func text(_ commit: HistoryCommit?, details: CommitDetails?) -> NSAttributedString {
        let text = NSMutableAttributedString()
        guard let commit else {
            text.append(NSAttributedString(string: T("Select a commit", "Selecione um commit"), attributes: [.font: UILooks.font(12), .foregroundColor: NSColor.secondaryLabelColor]))
            return text
        }
        let message = details?.message ?? commit.subject
        text.append(NSAttributedString(string: message + "\n\n", attributes: [.font: UILooks.font(13), .foregroundColor: NSColor.labelColor]))
        let date = HistoryRows.fullDates.string(from: commit.date)
        var meta = "\(commit.author) <\(commit.email)>\n\(date)\ncommit \(commit.sha)"
        if !commit.parents.isEmpty {
            let shas: [String] = commit.parents.map { String($0.prefix(7)) }
            let label = commit.parents.count > 1 ? T("parents", "pais") : T("parent", "pai")
            meta += "\n\(label) \(shas.joined(separator: " "))"
        }
        text.append(NSAttributedString(string: meta, attributes: [.font: UILooks.monospaced(11), .foregroundColor: NSColor.secondaryLabelColor]))
        return text
    }

    // MARK: Files

    func numberOfRows(in tableView: NSTableView) -> Int { shownFiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let file = shownFiles[row]
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.attributedStringValue = Self.line(file)
        label.toolTip = file.orig.isEmpty ? file.path : "\(file.orig) → \(file.path)"
        return label
    }

    /// A click, not a selection change: clicking the same file again opens
    /// its diff again (its tab may have been closed).
    @objc private func clicked(_ sender: Any?) {
        let row = files.clickedRow
        guard row >= 0, row < shownFiles.count else { return }
        onOpenFile?(shownFiles[row])
    }

    /// "M  src/a.zig  +3 −1", the letter in the color the Git panel uses.
    static func line(_ file: CommitDetails.File) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "\(file.letter)  ", attributes: [
            .font: UILooks.monospaced(11, weight: .bold), .foregroundColor: color(for: file.letter),
        ])
        let name = file.orig.isEmpty ? file.path : "\(file.orig) → \(file.path)"
        text.append(NSAttributedString(string: name, attributes: [.font: UILooks.font(12), .foregroundColor: NSColor.labelColor]))
        let small = UILooks.monospacedDigits(11)
        if let added = file.added, let removed = file.removed {
            text.append(NSAttributedString(string: "  +\(added)", attributes: [.font: small, .foregroundColor: NSColor.systemGreen]))
            text.append(NSAttributedString(string: " −\(removed)", attributes: [.font: small, .foregroundColor: NSColor.systemRed]))
        } else {
            text.append(NSAttributedString(string: T("  binary", "  binário"), attributes: [.font: small, .foregroundColor: NSColor.secondaryLabelColor]))
        }
        return text
    }

    /// The same colors as the Git panel's letters (source-control).
    static func color(for letter: Character) -> NSColor {
        switch letter {
        case "A": .systemGreen
        case "D": .systemRed
        case "R", "C": .systemBlue
        default: .systemOrange
        }
    }

    private func build() {
        info.isEditable = false
        info.isSelectable = true
        info.drawsBackground = false
        info.textContainerInset = NSSize(width: 10, height: 8)
        infoScroll.documentView = info
        infoScroll.hasVerticalScroller = true
        infoScroll.autohidesScrollers = true
        infoScroll.drawsBackground = false
        info.autoresizingMask = [.width]

        files.addTableColumn(NSTableColumn(identifier: .init("file")))
        files.headerView = nil
        files.rowHeight = UILooks.rowHeight(20)
        files.style = .plain
        files.backgroundColor = .clear
        files.dataSource = self
        files.delegate = self
        files.target = self
        files.action = #selector(clicked(_:))
        filesScroll.documentView = files
        filesScroll.hasVerticalScroller = true
        filesScroll.autohidesScrollers = true
        filesScroll.drawsBackground = false

        columns.setViews([infoScroll, filesScroll], in: .leading)
        columns.distribution = .fillEqually
        columns.spacing = 1
        columns.translatesAutoresizingMaskIntoConstraints = false
        addSubview(columns)
        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo: topAnchor),
            columns.leadingAnchor.constraint(equalTo: leadingAnchor),
            columns.trailingAnchor.constraint(equalTo: trailingAnchor),
            columns.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        show(nil, details: nil)
    }
}
