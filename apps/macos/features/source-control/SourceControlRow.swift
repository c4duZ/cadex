import AppKit
import Icons
import Menus

/// A row of the Git lists: a section title or a changed file.
enum SourceControlRow: Equatable {
    case header(title: String, staged: Bool?, count: Int)
    case entry(GitRepository.Entry, staged: Bool)

    /// Each list shows at most this many files (docs/spec/source-control.md).
    static let limit = 1000

    /// Conflicts first, then staged, then the other changes.
    static func rows(for status: GitRepository.Status) -> [SourceControlRow] {
        let conflicts = status.entries.filter { $0.kind == .conflict }
        let staged = status.entries.filter(\.isStaged)
        let changes = status.entries.filter(\.isUnstaged)
        var rows: [SourceControlRow] = []
        if !conflicts.isEmpty {
            rows.append(.header(title: "Conflitos", staged: nil, count: conflicts.count))
            rows += capped(conflicts, staged: false)
        }
        if !staged.isEmpty {
            rows.append(.header(title: "Staged", staged: true, count: staged.count))
            rows += capped(staged, staged: true)
        }
        if !changes.isEmpty || staged.isEmpty {
            rows.append(.header(title: changes.isEmpty && conflicts.isEmpty ? "Nenhuma mudança" : "Mudanças", staged: false, count: changes.count))
            rows += capped(changes, staged: false)
        }
        return rows
    }

    /// Thousands of rows made the table slow; the rest is in the terminal.
    private static func capped(_ entries: [GitRepository.Entry], staged: Bool) -> [SourceControlRow] {
        var rows = entries.prefix(limit).map { SourceControlRow.entry($0, staged: staged) }
        if entries.count > limit {
            rows.append(.header(title: "Mostrando \(limit) de \(entries.count): veja o resto com git status", staged: nil, count: 0))
        }
        return rows
    }

    /// The color of a change's letter (the explorer uses the same).
    static func color(for letter: Character) -> NSColor {
        switch letter {
        case "A", "?": .systemGreen
        case "D", "U": .systemRed
        case "R", "C": .systemBlue
        default: .systemOrange
        }
    }
}

/// One row: name, folder in grey, the change's letter, and a button to
/// stage (+) or unstage (−); section titles have it for every file.
@MainActor
final class SourceControlRowView: NSTableCellView {
    private let row: SourceControlRow
    private weak var controller: SourceControlController?

    init(_ row: SourceControlRow, controller: SourceControlController?) {
        self.row = row
        self.controller = controller
        super.init(frame: .zero)
        switch row {
        case let .header(title, staged, count): buildHeader(title, staged: staged, count: count)
        case let .entry(entry, staged): buildEntry(entry, staged: staged)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SourceControlRowView is created in code") }

    private func buildHeader(_ title: String, staged: Bool?, count: Int) {
        let label = NSTextField(labelWithString: count > 0 ? "\(title.uppercased())  \(count)" : title.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        var views: [NSView] = [label, NSView()]
        if let staged, count > 0 { views.append(actionButton(staged ? "−" : "+", tip: staged ? "Unstage tudo" : "Stage tudo")) }
        place(NSStackView(views: views))
    }

    private func buildEntry(_ entry: GitRepository.Entry, staged: Bool) {
        let name = (entry.path as NSString).lastPathComponent
        let folder = (entry.path as NSString).deletingLastPathComponent
        let label = NSTextField(labelWithString: "")
        let text = NSMutableAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let detail = entry.kind == .renamed ? (entry.orig as NSString).lastPathComponent + " → " : ""
        if !folder.isEmpty || !detail.isEmpty {
            text.append(NSAttributedString(string: "  " + detail + folder, attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        // One line, the folder cut at the end: the attributed text wrapped and the
        // folder ran over the next row (2026-10-19).
        let oneLine = NSMutableParagraphStyle()
        oneLine.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: oneLine, range: NSRange(location: 0, length: text.length))
        label.attributedStringValue = text
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.wraps = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let letter = entry.letter(staged: staged)
        let mark = NSTextField(labelWithString: String(letter))
        mark.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        mark.textColor = SourceControlRow.color(for: letter)
        let icon = NSImageView(image: Icon.file.image(size: 13))
        icon.contentTintColor = .secondaryLabelColor
        var views: [NSView] = [icon, label, NSView()]
        if entry.kind != .conflict { views.append(actionButton(staged ? "−" : "+", tip: staged ? "Unstage" : "Stage")) }
        views.append(mark)
        place(NSStackView(views: views))
        toolTip = entry.path
    }

    private func actionButton(_ title: String, tip: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: #selector(pressed))
        b.isBordered = false
        b.font = .systemFont(ofSize: 13, weight: .medium)
        b.toolTip = tip
        b.contentTintColor = .secondaryLabelColor
        return b
    }

    private func place(_ stack: NSStackView) {
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @objc private func pressed() {
        guard let controller else { return }
        switch row {
        case let .header(_, staged, _):
            if staged == true { controller.unstageAll() } else { controller.stageAll() }
        case let .entry(entry, staged):
            staged ? controller.unstage([entry]) : controller.stage([entry])
        }
    }
}

/// The lists' context menu: each item runs a registered command on the
/// clicked or selected files.
@MainActor
enum SourceControlMenu {
    static func entries(for view: SourceControlView) -> [MenuEntry] {
        let items: [(String, String, Icon)] = [
            ("Abrir o arquivo", "git.open-file", .file), ("Ver o diff", "git.open-diff", .gitDiff),
            ("Stage", "git.stage", .plus), ("Unstage", "git.unstage", .minus),
            ("Descartar as mudanças", "git.discard", .arrowUUpLeft), ("Revelar no Finder", "git.reveal", .folderOpen),
        ]
        return items.map { title, id, icon in
            MenuEntry(title, icon: icon) { [weak view] in _ = view?.controller?.run(id) }
        }
    }
}
