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
    static func task(_ task: WorkTreeTask) -> WorkTreeRow {
        typealias R = S.TaskRow
        let glyph = StateGlyphView(size: UILooks.pt(R.glyph), state: task.state)
        glyph.setContentHuggingPriority(.required, for: .horizontal)
        let name = label(task.name, size: R.Name.fontSize, weight: task.unread ? R.NameUnread.weight : R.Name.weight,
                         color: task.unread ? R.NameUnread.color : R.Name.color)
        let top = NSStackView(views: [glyph, name])
        top.spacing = UILooks.pt(R.gap)
        var lines: [NSView] = [top]
        if !task.agent.isEmpty {
            let meta = label(task.agent, size: R.Meta.fontSize, color: R.Meta.color)
            let indented = NSStackView(views: [meta])
            indented.edgeInsets = NSEdgeInsets(top: 0, left: UILooks.pt(R.Meta.indent), bottom: 0, right: 0)
            lines.append(indented)
        }
        let row = WorkTreeRow(views: lines)
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = UILooks.pt(R.Meta.marginTop)
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(R.padding.top), left: UILooks.pt(R.padding.left),
                                      bottom: UILooks.pt(R.padding.bottom), right: UILooks.pt(R.padding.right))
        row.radius = R.radius
        row.setAccessibilityRole(.button)
        row.setAccessibilityLabel(task.name)
        return row
    }

    /// A terminal: its state's dot (or a quiet one), the name, the note on the right.
    static func terminal(_ terminal: WorkTreeTerminal) -> WorkTreeRow {
        typealias T = S.TerminalRow
        let dot = StateGlyphView(size: UILooks.pt(T.dot), state: terminal.state ?? .idle)
        dot.setContentHuggingPriority(.required, for: .horizontal)
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
        var views: [NSView] = [Self.icon(icon, size: F.icon, color: F.color), label(title, size: S.Project.fontSize, color: F.color)]
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
