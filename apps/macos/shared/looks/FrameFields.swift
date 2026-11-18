import AppKit

/// A box of the new frame: its fill, line and corner, its content held inside a padding.
@MainActor
public class FrameBox: NSView {
    public override var isFlipped: Bool { true }

    public func box(bg: NSColor?, border: NSColor?, radius: CGFloat) {
        wantsLayer = true
        layer?.backgroundColor = bg?.cgColor
        layer?.borderColor = border?.cgColor
        layer?.borderWidth = border == nil ? 0 : DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(radius)
    }

    public func hold(_ content: NSView, padding: NSEdgeInsets) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: UILooks.pt(padding.left)),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -UILooks.pt(padding.right)),
            content.topAnchor.constraint(equalTo: topAnchor, constant: UILooks.pt(padding.top)),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -UILooks.pt(padding.bottom)),
        ])
    }
}

/// The form controls of the new frame (plan 31 B): the system's own fields, popups and text areas
/// without their bezels, inside the New Task request's box (components.newTask.field), with the
/// interface's font and the frame's text colors; the section's small capital label above each.
@MainActor
public enum FrameField {
    typealias NT = DesignTokens.NewTask

    /// One line of the interface's text.
    public static func text(_ string: String, size: CGFloat = DesignTokens.FontSize.body, color: NSColor = DesignTokens.Color.textBody,
                            weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = UILooks.font(size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// Words that wrap to the width (a sheet's explanation).
    public static func wrapping(_ string: String, color: NSColor = DesignTokens.Color.textMuted) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = UILooks.font(DesignTokens.FontSize.meta)
        label.textColor = color
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    /// "NAME", "WHEN": the section's label of New Task.
    public static func label(_ string: String) -> NSTextField {
        typealias L = NT.Label
        let label = text(string.uppercased(), size: L.fontSize, color: L.color, weight: L.weight)
        label.attributedStringValue = NSAttributedString(string: string.uppercased(), attributes: [
            .font: UILooks.font(L.fontSize, weight: L.weight), .foregroundColor: L.color, .kern: UILooks.pt(L.fontSize) * L.tracking,
        ])
        return label
    }

    public static func column(_ views: [NSView], gap: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = UILooks.pt(gap)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    /// The label over its control, the control across the column.
    public static func labeled(_ title: String, _ control: NSView) -> NSView {
        let stack = column([label(title), control], gap: NT.Frame.labelBottom)
        control.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Controls side by side in one row, sharing it.
    public static func row(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.spacing = UILooks.pt(NT.Option.gap)
        stack.distribution = .fillEqually
        return stack
    }

    /// The request's box around a control (its fill, line and corner; a shorter padding).
    static func boxed(_ control: NSView) -> FrameBox {
        let box = FrameBox()
        box.box(bg: NT.Field.bg, border: NT.Field.border, radius: NT.Field.radius)
        box.hold(control, padding: NT.AgentRow.padding)
        return box
    }

    /// A text field without its bezel, in the box.
    public static func field(_ field: NSTextField) -> NSView {
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = UILooks.font(DesignTokens.FontSize.body)
        field.textColor = DesignTokens.Color.textPrimary
        if let hint = field.placeholderString {
            field.placeholderAttributedString = NSAttributedString(string: hint, attributes: [
                .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: DesignTokens.Color.textTertiary,
            ])
        }
        return boxed(field)
    }

    /// A popup without its bezel, its items in the interface's font, in the box.
    public static func popup(_ popup: NSPopUpButton) -> NSView {
        popup.isBordered = false
        popup.font = UILooks.font(DesignTokens.FontSize.body)
        paint(popup)
        return boxed(popup)
    }

    /// The popup's items again in the frame's colors (after items change).
    public static func paint(_ popup: NSPopUpButton) {
        for item in popup.itemArray {
            item.attributedTitle = NSAttributedString(string: item.title, attributes: [
                .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: DesignTokens.Color.textPrimary,
            ])
        }
    }

    /// A combo box (a list with typing), without its bezel, in the box.
    public static func combo(_ combo: NSComboBox) -> NSView {
        combo.isBordered = false
        combo.isButtonBordered = false
        combo.drawsBackground = false
        combo.focusRingType = .none
        combo.font = UILooks.font(DesignTokens.FontSize.body)
        combo.textColor = DesignTokens.Color.textPrimary
        return boxed(combo)
    }

    /// Several lines of plain text (a prompt), in the box, at least `height` tall.
    public static func area(_ view: NSTextView, height: CGFloat) -> NSView {
        view.isRichText = false
        view.font = UILooks.font(DesignTokens.FontSize.body)
        view.textColor = DesignTokens.Color.textPrimary
        view.insertionPointColor = DesignTokens.Color.textPrimary
        view.drawsBackground = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainerInset = .zero
        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.heightAnchor.constraint(equalToConstant: UILooks.pt(height)).isActive = true
        let box = FrameBox()
        box.box(bg: NT.Field.bg, border: NT.Field.border, radius: NT.Field.radius)
        box.hold(scroll, padding: NT.Field.padding)
        return box
    }

    /// A checkbox whose title is in the interface's font and the frame's text color.
    public static func check(_ button: NSButton) -> NSButton {
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .font: UILooks.font(DesignTokens.FontSize.body), .foregroundColor: DesignTokens.Color.textBody,
        ])
        return button
    }
}
