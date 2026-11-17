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

/// Last turn / Task / Uncommitted (components.inspector.segmented): the chosen one raised.
@MainActor
final class ChangesSegmented: NSView {
    typealias S = DesignTokens.Inspector.Segmented
    var onPick: ((ChangesScope) -> Void)?
    private var segments: [(ChangesScope, NSTextField, NSView)] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = S.bg.cgColor
        layer?.borderColor = S.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(S.radius)
        let stack = NSStackView()
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: UILooks.pt(S.padding), left: UILooks.pt(S.padding), bottom: UILooks.pt(S.padding), right: UILooks.pt(S.padding))
        for scope in ChangesScope.allCases {
            let box = NSView()
            box.wantsLayer = true
            box.layer?.cornerRadius = UILooks.pt(S.Segment.Active.radius)
            let text = NSTextField(labelWithString: scope.title)
            text.alignment = .center
            text.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(text)
            NSLayoutConstraint.activate([
                text.centerXAnchor.constraint(equalTo: box.centerXAnchor),
                text.topAnchor.constraint(equalTo: box.topAnchor, constant: UILooks.pt(S.Segment.padding.top)),
                text.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -UILooks.pt(S.Segment.padding.bottom)),
            ])
            box.setAccessibilityRole(.button)
            box.setAccessibilityLabel(scope.title)
            stack.addArrangedSubview(box)
            segments.append((scope, text, box))
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ChangesSegmented is created in code") }

    override var mouseDownCanMoveWindow: Bool { false }

    func select(_ chosen: ChangesScope) {
        for (scope, text, box) in segments {
            let on = scope == chosen
            box.layer?.backgroundColor = on ? S.Segment.Active.bg.cgColor : nil
            text.font = on ? UILooks.font(S.Segment.fontSize, weight: S.Segment.Active.weight) : UILooks.font(S.Segment.fontSize)
            text.textColor = on ? DesignTokens.Color.textPrimary : S.Segment.Inactive.color
        }
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = segments.first(where: { $0.2.convert($0.2.bounds, to: self).contains(point) }) else { return }
        onPick?(hit.0)
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
