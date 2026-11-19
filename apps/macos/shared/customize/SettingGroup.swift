import AppKit
import UILooks

/// A settings section as macOS's own settings lay it (the owner, 2026-11-19, on the project's
/// Settings: too much explaining, no hierarchy, uneven spacing): a small label, then ONE box with
/// the section's rows and a hairline between them, the same padding in every row and the same gap
/// between sections (components.project.group). A row is its name, at most a short line under it,
/// and its control on the right. The project's Settings (the projects feature) and its memory's
/// form (the memory feature) use it, so it lives here beside the switch.
@MainActor
public enum SettingGroup {
    typealias G = DesignTokens.Project.Group

    /// The section: the label (none: just the box) over the rows, a line between each two.
    public static func section(_ title: String?, _ rows: [NSView]) -> NSView {
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 0
        for (index, row) in rows.enumerated() {
            if index > 0 { add(divider(), to: inner) }
            add(row, to: inner)
        }
        let box = FrameBox()
        box.box(bg: G.bg, border: G.border, radius: G.radius)
        box.hold(inner, padding: NSEdgeInsetsZero)
        guard let title else { return box }
        let column = NSStackView(views: [label(title), box])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(G.labelGap)
        box.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    /// One row: the name, an optional short line under it, the control on the right.
    public static func row(_ title: String, _ detail: String? = nil, _ control: NSView?) -> NSView {
        let name = NSTextField(labelWithString: title)
        name.font = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.medium)
        name.textColor = DesignTokens.Color.textPrimary
        name.lineBreakMode = .byTruncatingTail
        var words: [NSView] = [name]
        if let detail {
            let line = NSTextField(wrappingLabelWithString: detail)
            line.font = UILooks.font(DesignTokens.FontSize.small)
            line.textColor = DesignTokens.Color.textMuted
            words.append(line)
        }
        let left = NSStackView(views: words)
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = UILooks.pt(G.textGap)
        left.setHuggingPriority(.init(1), for: .horizontal)
        left.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var views: [NSView] = [left]
        if let control {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            views.append(control)
        }
        let line = NSStackView(views: views)
        line.alignment = .centerY
        line.spacing = UILooks.pt(G.gap)
        let row = FrameBox()
        row.hold(line, padding: G.padding)
        return row
    }

    /// The project page's switch (components.project.toggle).
    public static func toggle(_ on: Bool, _ changed: @escaping (Bool) -> Void) -> NSView {
        let control = ThemeSwitch(on: on, accent: DesignTokens.Project.Toggle.on, off: DesignTokens.Project.Toggle.off, label: "")
        control.onChange = changed
        return control
    }

    /// The section's small capital label, as the other pages' (components.project.label).
    static func label(_ title: String) -> NSTextField {
        typealias L = DesignTokens.Project.Label
        let label = NSTextField(labelWithString: title.uppercased())
        label.attributedStringValue = NSAttributedString(string: title.uppercased(), attributes: [
            .font: UILooks.font(L.fontSize, weight: L.weight), .foregroundColor: L.color, .kern: UILooks.pt(L.fontSize) * L.tracking,
        ])
        return label
    }

    private static func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = G.divider.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline).isActive = true
        return line
    }

    private static func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        let inset = view is FrameBox ? 0 : UILooks.pt(G.padding.left)
        view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: inset).isActive = true
        view.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true
    }
}
