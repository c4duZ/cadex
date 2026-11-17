import AppKit

/// The new frame's button (components.button): primary, white on dark; secondary, the dark one with
/// a line. The bell's cards and the right panel's Changes footer use it (plan 26), so it lives here.
@MainActor
public enum DesignButton {
    public enum Style { case primary, secondary }

    /// `fill`: no width of its own, it takes what its row gives (Changes' footer, two halves);
    /// otherwise as wide as its title and padding.
    public static func make(_ title: String, _ style: Style, height: CGFloat = DesignTokens.Button.Heights.medium, fill: Bool = false,
                            action: @escaping @MainActor () -> Void) -> NSButton {
        typealias B = DesignTokens.Button
        let button = DesignButtonView(title: title, target: nil, action: nil)
        button.handler = action
        button.target = button
        button.action = #selector(DesignButtonView.clicked)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = UILooks.pt(B.radius)
        let color: NSColor
        let weight: NSFont.Weight
        switch style {
        case .primary:
            button.layer?.backgroundColor = B.Primary.bg.cgColor
            color = B.Primary.color
            weight = B.Primary.weight
        case .secondary:
            button.layer?.backgroundColor = B.Secondary.bg.cgColor
            button.layer?.borderColor = B.Secondary.border.cgColor
            button.layer?.borderWidth = DesignTokens.Stroke.hairline
            color = B.Secondary.color
            weight = B.Secondary.weight
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: UILooks.font(DesignTokens.FontSize.body, weight: weight), .foregroundColor: color,
        ])
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: UILooks.pt(height)).isActive = true
        if !fill {
            button.widthAnchor.constraint(equalToConstant: ceil(button.attributedTitle.size().width) + UILooks.pt(B.paddingX[1]) * 2).isActive = true
        }
        return button
    }
}

/// The button's own class: its click runs a closure (the caller runs a command by id, ADR 0005).
public final class DesignButtonView: NSButton {
    var handler: (@MainActor () -> Void)?
    @objc func clicked() { handler?() }
}
