import AppKit
import Icons
import StateGlyph
import Strings
import UILooks

/// A pressable row of the tree: the click runs `onPress`; chosen, the drawing's raised fill with its
/// 1 pt line inside (components.sidebar.*.selected).
@MainActor
final class WorkTreeRow: NSStackView {
    var onPress: (() -> Void)?
    /// The right click, at the point in the row (a task's menu).
    var onMenu: ((NSPoint) -> Void)?
    var radius: CGFloat = 0
    var isChosen = false { didSet { needsDisplay = true; restyle() } }
    private var hovering = false { didSet { restyle() } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?()
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let onMenu else { return super.rightMouseDown(with: event) }
        onMenu(convert(event.locationInWindow, from: nil))
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return onPress != nil
    }

    private func restyle() {
        wantsLayer = true
        typealias Selected = DesignTokens.Sidebar.TaskRow.Selected
        layer?.cornerRadius = UILooks.pt(radius)
        layer?.backgroundColor = isChosen ? Selected.bg.cgColor : hovering ? DesignTokens.Color.bgCard.cgColor : nil
        let line = Selected.shadow.first
        layer?.borderColor = isChosen ? line?.color.cgColor : nil
        layer?.borderWidth = isChosen ? (line?.spread ?? 0) : 0
    }
}

@MainActor
enum WorkTreeRows {
    typealias S = DesignTokens.Sidebar

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight? = nil, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = weight.map { UILooks.font(size, weight: $0) } ?? UILooks.font(size)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    static func icon(_ icon: Icon, size: CGFloat, color: NSColor) -> NSImageView {
        let view = NSImageView(image: icon.image(size: UILooks.pt(size)))
        view.contentTintColor = color
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    /// A state glyph that takes only its design size in the row; the halo draws past it, as the
    /// mockup's box-shadow takes no room (the name sat 6 pt off, measured 2026-11-17).
    private static func designSized(_ glyph: StateGlyphView, _ side: CGFloat) -> StateGlyphView {
        glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(side)).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(side)).isActive = true
        return glyph
    }

    private static func spacer() -> NSView {
        let view = NSView()
        view.setContentHuggingPriority(.init(1), for: .horizontal)
        return view
    }

    /// "▾ cadex  main  3": the caret folds the project (`fold`); the rest of the row opens it.
    static func project(_ project: WorkTreeProject, folded: Bool, fold: @escaping @MainActor () -> Void) -> WorkTreeRow {
        typealias P = S.Project
        let caret = WorkTreeRow(views: [icon(folded ? .caretRight : .caretDown, size: P.chevron, color: P.detail)])
        caret.onPress = fold
        caret.setAccessibilityRole(.disclosureTriangle)
        caret.setAccessibilityLabel(folded ? T("Unfold", "Desdobrar") : T("Fold", "Dobrar"))
        let name = label(project.name, size: P.fontSize, weight: P.Name.weight, color: P.Name.color)
        var views: [NSView] = [caret, name]
        if !project.branch.isEmpty { views.append(label(project.branch, size: P.fontSize, color: P.detail)) }
        views.append(spacer())
        if !project.tasks.isEmpty {
            views.append(label("\(project.tasks.count)", size: P.fontSize, color: P.detail))
        }
        let row = WorkTreeRow(views: views)
        row.spacing = UILooks.pt(P.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(P.paddingX), bottom: 0, right: UILooks.pt(P.paddingX))
        row.radius = P.radius
        row.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(P.height)).isActive = true
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(project.name)
        return row
    }

    /// The task's line (the anatomy): its state, its name (bold when there is news), and under it
    /// who works on it.
    static func task(_ task: WorkTreeTask, terminals: [WorkTreeRow] = []) -> WorkTreeRow {
        typealias R = S.TaskRow
        typealias T = S.TerminalRow
        let glyph = designSized(StateGlyphView(size: R.glyph, state: task.state), R.glyph)
        let name = label(task.name, size: R.Name.fontSize, weight: task.unread ? R.NameUnread.weight : R.Name.weight,
                         color: task.unread ? R.NameUnread.color : R.Name.color)
        var head: [NSView] = [glyph, name, spacer()]
        if !task.age.isEmpty { head.append(label(task.age, size: R.Age.fontSize, color: R.Age.color)) }
        let top = NSStackView(views: head)
        top.spacing = UILooks.pt(R.gap)
        var lines: [NSView] = [top]
        // Under the name: the agent · +added −removed · what it waits for (the anatomy).
        var meta: [NSView] = []
        func dot() { if !meta.isEmpty { meta.append(label("·", size: R.Meta.fontSize, color: R.separator)) } }
        if !task.agent.isEmpty { meta.append(label(task.agent, size: R.Meta.fontSize, color: R.Meta.color)) }
        if let added = task.added, let removed = task.removed {
            dot()
            meta.append(label("+\(added)", size: R.Meta.fontSize, color: R.added))
            meta.append(label("−\(removed)", size: R.Meta.fontSize, color: R.removed))
        }
        if !task.waiting.isEmpty {
            dot()
            meta.append(label(task.waiting, size: R.Meta.fontSize, color: R.waiting))
        }
        if !meta.isEmpty {
            let line = NSStackView(views: meta)
            line.spacing = UILooks.pt(R.Meta.gap)
            line.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(R.Meta.indent), bottom: 0, right: 0)
            lines.append(line)
        }
        let block = NSStackView(views: terminals)
        if !terminals.isEmpty {
            block.orientation = .vertical
            block.alignment = .leading
            block.spacing = UILooks.pt(T.Block.gap)
            lines.append(block)
        }
        let row = WorkTreeRow(views: lines)
        if !terminals.isEmpty { row.setCustomSpacing(UILooks.pt(T.Block.marginTop), after: lines[lines.count - 2]) }
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = UILooks.pt(R.Meta.marginTop)
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(R.padding.top), left: UILooks.pt(R.padding.left),
                                      bottom: UILooks.pt(R.padding.bottom), right: UILooks.pt(R.padding.right))
        row.radius = R.radius
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(task.name)
        row.toolTip = task.comment.isEmpty ? nil : task.comment
        top.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -UILooks.pt(R.padding.left + R.padding.right)).isActive = true
        for terminal in terminals {
            terminal.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -UILooks.pt(R.padding.left + R.padding.right + T.Block.indent)).isActive = true
        }
        if !terminals.isEmpty {
            block.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(T.Block.indent), bottom: 0, right: 0)
        }
        return row
    }

    /// A terminal: its state's dot (or a quiet one), the name, the note on the right.
    static func terminal(_ terminal: WorkTreeTerminal) -> WorkTreeRow {
        typealias T = S.TerminalRow
        let dot = designSized(StateGlyphView(size: T.dot, state: terminal.state ?? .idle), T.dot)
        var views: [NSView] = [dot, label(terminal.title, size: T.fontSize, color: T.color), spacer()]
        if !terminal.note.isEmpty { views.append(label(terminal.note, size: T.Note.fontSize, color: T.Note.color)) }
        let row = WorkTreeRow(views: views)
        row.spacing = UILooks.pt(T.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(T.padding.left), bottom: 0, right: UILooks.pt(T.padding.right))
        row.radius = T.radius
        row.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(T.height)).isActive = true
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(terminal.title)
        return row
    }

    /// "+ Add project".
    static func addProject(_ title: String) -> WorkTreeRow {
        typealias A = S.AddProject
        let row = WorkTreeRow(views: [icon(.plus, size: A.fontSize, color: A.color), label(title, size: A.fontSize, color: A.color)])
        row.spacing = UILooks.pt(A.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(A.paddingX), bottom: 0, right: UILooks.pt(A.paddingX))
        row.radius = S.Project.radius
        row.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(A.height)).isActive = true
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(title)
        return row
    }

    /// A row of the foot: "Automations · 2 on", "Archive & history".
    static func foot(_ icon: Icon, _ title: String, detail: String) -> WorkTreeRow {
        typealias F = S.Foot.Row
        let name = label(title, size: S.Project.fontSize, color: F.color)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        var views: [NSView] = [Self.icon(icon, size: F.icon, color: F.color), name]
        if !detail.isEmpty { views.append(label(detail, size: F.Detail.fontSize, color: F.Detail.color)) }
        let row = WorkTreeRow(views: views)
        row.spacing = UILooks.pt(F.gap)
        row.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(F.paddingX), bottom: 0, right: UILooks.pt(F.paddingX))
        row.radius = S.Project.radius
        row.heightAnchor.constraint(equalToConstant: UILooks.rowHeight(F.height)).isActive = true
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(title)
        return row
    }
}
