import AppKit
import StateGlyph
import Strings
import UILooks

/// The pieces of the bell's popover (AgentAttentionView; components.bell and components.button of
/// the new frame's tokens): its buttons and the line of a card.
@MainActor
enum AgentBellParts {
    enum Style { case primary, secondary, quiet }

    /// Allow (primary), Deny (secondary), Go to tab (quiet), as the mockup draws them.
    static func button(_ title: String, _ style: Style, _ action: @escaping @MainActor () -> Void) -> NSButton {
        typealias B = DesignTokens.Button
        let button = BellButton(title: title, target: nil, action: nil)
        button.handler = action
        button.target = button
        button.action = #selector(BellButton.clicked)
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
        case .quiet:
            color = DesignTokens.Bell.GoTo.color
            weight = .regular
        }
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: UILooks.font(DesignTokens.FontSize.body, weight: weight), .foregroundColor: color,
        ])
        let padding = style == .quiet ? DesignTokens.Bell.GoTo.padding.left : B.paddingX[1]
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: UILooks.pt(B.Heights.medium)),
            button.widthAnchor.constraint(equalToConstant: ceil(button.attributedTitle.size().width) + UILooks.pt(padding) * 2),
        ])
        return button
    }

    /// A label in the popover's type: a size, a weight and a color of the tokens.
    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor, wraps: Bool = false) -> NSTextField {
        let label = wraps ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        label.font = UILooks.font(size, weight: weight)
        label.textColor = color
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        return label
    }

    /// A glyph, the text and the time, as a card's heading and an earlier line are.
    static func line(_ state: GlyphState, glyph size: CGFloat, _ text: NSView, time: String) -> NSStackView {
        let glyph = StateGlyphView(size: size, state: state)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let when = label(time, size: DesignTokens.Bell.Card.Time.fontSize, color: DesignTokens.Bell.Card.Time.color)
        let row = NSStackView(views: [glyph, text, spacer, when])
        row.spacing = UILooks.pt(DesignTokens.Bell.Card.gap)
        return row
    }
}

/// A button that runs a closure.
final class BellButton: NSButton {
    var handler: (@MainActor () -> Void)?
    @objc func clicked() { handler?() }
}
