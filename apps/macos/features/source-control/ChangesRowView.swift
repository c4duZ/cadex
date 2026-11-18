import AppKit
import UILooks
import Icons
import Menus
import Strings

/// A changed file in the Changes tab (components.inspector.fileRow): the letter (M amber, A green,
/// D red), the name with its folder after it, and +added −removed on the right.
@MainActor
final class ChangesRowView: NSView {
    typealias F = DesignTokens.Inspector.FileRow

    init(_ row: ChangesRow) {
        super.init(frame: .zero)
        let kind = label(String(row.letter), size: F.Kind.fontSize, weight: F.Kind.weight, color: Self.color(of: row.letter))
        // Left in its 14 pt, as the mockup's span; centered it sat 4 pt right (measured 2026-11-17).
        kind.alignment = .left
        let name = NSTextField(labelWithString: "")
        // One line, cut at the end: a long folder wrapped onto the next row (seen 2026-11-17).
        name.usesSingleLineMode = true
        name.maximumNumberOfLines = 1
        name.cell?.wraps = false
        name.cell?.truncatesLastVisibleLine = true
        name.attributedStringValue = Self.title(row)
        name.lineBreakMode = .byTruncatingTail
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        var views: [NSView] = [kind, name]
        if let added = row.file.added, let removed = row.file.removed {
            views.append(label("+\(added)", size: F.Count.fontSize, color: DesignTokens.Color.accentGreenText))
            views.append(label("−\(removed)", size: F.Count.fontSize, color: DesignTokens.Color.accentRedText))
        }
        let stack = NSStackView(views: views)
        stack.spacing = UILooks.pt(F.gap)
        stack.distribution = .fill
        // Less the 2 pt a label draws its text in, at both ends: the letter, the name and the counts
        // land where the mockup has them (measured 2026-11-17).
        let inset = UILooks.labelInset
        stack.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(F.padding.left) - inset, bottom: 0, right: UILooks.pt(F.padding.right) - inset)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            kind.widthAnchor.constraint(equalToConstant: UILooks.pt(F.Kind.width)),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityLabel(row.file.path)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ChangesRowView is created in code") }

    static func color(of letter: Character) -> NSColor {
        switch letter {
        case "A": F.Kind.added
        case "D", "U": DesignTokens.Color.accentRedText
        case "M", "T": F.Kind.modified
        default: F.dir
        }
    }

    /// "name  folder": the folder after two spaces, dimmer, as the mockup.
    static func title(_ row: ChangesRow) -> NSAttributedString {
        let cut = NSMutableParagraphStyle()
        cut.lineBreakMode = .byTruncatingTail
        let text = NSMutableAttributedString(string: row.name, attributes: [.paragraphStyle: cut,
            .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: DesignTokens.Color.textPrimary,
        ])
        // Staged or not is not in the counts (they are against HEAD): said after the name.
        if let state = row.stagedNote {
            text.append(NSAttributedString(string: "  · " + state, attributes: [.paragraphStyle: cut,
                .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: F.dir,
            ]))
        }
        if !row.folder.isEmpty {
            text.append(NSAttributedString(string: "  " + row.folder, attributes: [.paragraphStyle: cut,
                .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: F.dir,
            ]))
        }
        return text
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight? = nil, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = weight.map { UILooks.font(size, weight: $0) } ?? UILooks.font(size)
        field.textColor = color
        field.setContentHuggingPriority(.required, for: .horizontal)
        field.setContentCompressionResistancePriority(.required, for: .horizontal)
        return field
    }
}


/// What Changes shows (plan 36 phase C; docs/adr/0038-rail-and-side-column.md): the scope in a small
/// menu ("Last turn ▾"; the three-part control did not fit the 260 pt column) and beside it the
/// total of the scope, "4 files · +96 −15". Each scope's line runs its command (ADR 0005).
@MainActor
final class ChangesSegmented: NSView {
    typealias S = DesignTokens.Inspector.Segmented
    var onPick: ((ChangesScope) -> Void)?
    private let scopeBox = NSView()
    private let scopeLabel = NSTextField(labelWithString: "")
    private let caret = NSImageView()
    let total = NSTextField(labelWithString: "")
    private(set) var chosen: ChangesScope = .lastTurn

    init() {
        super.init(frame: .zero)
        scopeBox.wantsLayer = true
        scopeBox.layer?.backgroundColor = S.Segment.Active.bg.cgColor
        scopeBox.layer?.cornerRadius = UILooks.pt(S.Segment.Active.radius)
        scopeLabel.font = UILooks.font(S.Segment.fontSize, weight: S.Segment.Active.weight)
        scopeLabel.textColor = DesignTokens.Color.textPrimary
        caret.image = Icon.caretDown.image(size: UILooks.pt(S.Segment.fontSize))
        caret.contentTintColor = S.Segment.Inactive.color
        total.font = UILooks.font(S.Segment.fontSize)
        total.textColor = S.Segment.Inactive.color
        total.lineBreakMode = .byTruncatingTail
        total.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let inner = NSStackView(views: [scopeLabel, caret])
        inner.spacing = UILooks.pt(S.padding)
        inner.edgeInsets = NSEdgeInsets(top: UILooks.pt(S.Segment.padding.top), left: UILooks.pt(S.padding) * 3,
                                        bottom: UILooks.pt(S.Segment.padding.bottom), right: UILooks.pt(S.padding) * 2)
        inner.translatesAutoresizingMaskIntoConstraints = false
        scopeBox.addSubview(inner)
        let row = NSStackView(views: [scopeBox, total])
        row.alignment = .centerY
        row.spacing = UILooks.pt(S.padding) * 3
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: scopeBox.topAnchor), inner.bottomAnchor.constraint(equalTo: scopeBox.bottomAnchor),
            inner.leadingAnchor.constraint(equalTo: scopeBox.leadingAnchor), inner.trailingAnchor.constraint(equalTo: scopeBox.trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        scopeBox.setAccessibilityRole(.popUpButton)
        select(.lastTurn)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ChangesSegmented is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func select(_ scope: ChangesScope) {
        chosen = scope
        scopeLabel.stringValue = scope.title
        scopeBox.setAccessibilityLabel(scope.title)
    }

    /// The scope's total: "4 files · +96 −15" (the lines only when git counted them).
    func setTotal(files: Int, added: Int, removed: Int) {
        let words = files == 1 ? T("1 file", "1 arquivo") : T("\(files) files", "\(files) arquivos")
        let text = NSMutableAttributedString(string: words, attributes: [.foregroundColor: S.Segment.Inactive.color, .font: UILooks.font(S.Segment.fontSize)])
        if files > 0 {
            text.append(NSAttributedString(string: " · ", attributes: [.foregroundColor: S.Segment.Inactive.color, .font: UILooks.font(S.Segment.fontSize)]))
            text.append(NSAttributedString(string: "+\(added)", attributes: [.foregroundColor: DesignTokens.Color.accentGreenText, .font: UILooks.font(S.Segment.fontSize)]))
            text.append(NSAttributedString(string: " −\(removed)", attributes: [.foregroundColor: DesignTokens.Color.accentRedText, .font: UILooks.font(S.Segment.fontSize)]))
        }
        total.attributedStringValue = text
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard scopeBox.convert(scopeBox.bounds, to: self).contains(point) else { return }
        PopupMenu.show(ChangesScope.allCases.map { scope in
            MenuEntry(scope.title, icon: scope == chosen ? .check : nil) { [weak self] in self?.onPick?(scope) }
        }, below: scopeBox)
    }
}

/// The lists' context menu: each item runs a registered command on the
/// clicked or selected files. Only what applies to them shows (owner,
/// 2026-10-20): Stage on changes, Unstage on staged ones, and no file to
/// open or reveal when every one was deleted. The diff and the file open
/// where the setting says, beside or in a new tab.
@MainActor
enum SourceControlMenu {
    static func entries(for view: SourceControlView) -> [MenuEntry] {
        let picked = view.selectedEntries()
        guard !picked.isEmpty else { return [] }
        let onDisk = picked.contains { !isDeleted($0.0, staged: $0.1) }
        let items: [(String, String, Icon, Bool)?] = [
            (T("Open File", "Abrir o arquivo"), "git.open-file", .file, onDisk),
            (T("Open Beside", "Abrir ao lado"), "git.open-file-beside", .squareSplitHorizontal, onDisk),
            (T("Open in New Tab", "Abrir em nova aba"), "git.open-file-in-tab", .plus, onDisk),
            nil,
            (T("Open Diff", "Ver o diff"), "git.open-diff", .gitDiff, true),
            (T("Open Diff Beside", "Ver o diff ao lado"), "git.open-diff-beside", .squareSplitHorizontal, true),
            (T("Open Diff in New Tab", "Ver o diff em nova aba"), "git.open-diff-in-tab", .plus, true),
            nil,
            ("Stage", "git.stage", .plus, picked.contains { !$0.1 }),
            ("Unstage", "git.unstage", .minus, picked.contains { $0.1 }),
            (T("Discard Changes", "Descartar as mudanças"), "git.discard", .arrowUUpLeft, true),
            nil,
            (T("Reveal in Finder", "Revelar no Finder"), "git.reveal", .folderOpen, onDisk),
        ]
        return items.compactMap { item in
            guard let (title, id, icon, applies) = item else { return .separator }
            guard applies else { return nil }
            return MenuEntry(title, icon: icon) { [weak view] in _ = view?.controller?.run(id) }
        }
    }

    /// Gone from the disk: deleted in the working tree, or staged as
    /// deleted with nothing after.
    static func isDeleted(_ entry: GitRepository.Entry, staged: Bool) -> Bool {
        staged ? entry.index == "D" && entry.worktree == "." : entry.worktree == "D"
    }
}
