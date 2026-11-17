import AppKit
import StateGlyph
import Strings
import UILooks

/// The permission an agent asks for, at the foot of its pane (plan 28 phase D; the Pane mockup,
/// components.pane.permission): the amber glyph, "Wants to run Bash" over the command, Allow and
/// Deny. The same request the bell shows: answering here or there closes both, as both read
/// AgentAttention. The app puts it in the terminal's foot (TerminalView.footCard).
@MainActor
public final class AgentPermissionCard: NSView {
    typealias P = DesignTokens.Pane.Permission
    public let requestID: String

    public init(_ request: AgentRequest, allow: @escaping @MainActor () -> Void, deny: @escaping @MainActor () -> Void) {
        requestID = request.id
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = UILooks.pt(P.radius)
        layer?.backgroundColor = P.bg.cgColor
        layer?.borderColor = P.border.cgColor
        layer?.borderWidth = DesignTokens.Stroke.hairline
        if let shadow = P.shadow.first {
            layer?.shadowColor = shadow.color.cgColor
            layer?.shadowOpacity = 1
            layer?.shadowRadius = UILooks.pt(shadow.layerRadius)
            layer?.shadowOffset = shadow.offset
        }
        let glyph = StateGlyphView(size: P.glyph, state: .needs)
        glyph.widthAnchor.constraint(equalToConstant: UILooks.pt(P.glyph)).isActive = true
        glyph.heightAnchor.constraint(equalToConstant: UILooks.pt(P.glyph)).isActive = true
        let title = request.title.trimmingCharacters(in: .whitespaces)
        let heading = NSTextField(labelWithString: title.isEmpty ? T("Waiting for a permission", "Esperando uma permissão")
                                                                  : T("Wants to run \(title)", "Quer rodar \(title)"))
        heading.font = UILooks.font(P.Title.fontSize, weight: P.Title.weight)
        heading.textColor = DesignTokens.Color.textPrimary
        let command = NSTextField(labelWithString: request.detail)
        command.font = UILooks.monospaced(P.Command.fontSize)
        command.textColor = P.Command.color
        command.lineBreakMode = .byTruncatingTail
        command.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let words = NSStackView(views: request.detail.isEmpty ? [heading] : [heading, command])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = UILooks.pt(DesignTokens.Stroke.glyph)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let allowButton = DesignButton.make(T("Allow", "Permitir"), .primary, height: P.Allow.height, action: allow)
        let denyButton = DesignButton.make(T("Deny", "Negar"), .secondary, height: P.Deny.height, action: deny)
        // The mockup's Deny: no fill, the amber line.
        denyButton.layer?.backgroundColor = nil
        denyButton.layer?.borderColor = P.Deny.border.cgColor
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [glyph, words, spacer, allowButton, denyButton])
        row.spacing = UILooks.pt(P.gap)
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(P.padding.top), left: UILooks.pt(P.padding.left),
                                      bottom: UILooks.pt(P.padding.bottom), right: UILooks.pt(P.padding.right))
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(heading.stringValue)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("AgentPermissionCard is created in code") }

    public override var mouseDownCanMoveWindow: Bool { false }
}
