import AppKit
import Editor
import Icons
import Menus
import Strings

/// The button at the top right of a note's tab: "Visualizar" over the text,
/// "Código" over the rendered page. It runs markdown.toggle-preview, the
/// same command as ⇧⌘V (ADR 0005). Without it nobody found the rendered
/// view (owner, 2026-10-19).
@MainActor
final class MarkdownToggle: NSView {
    var onPress: (() -> Void)?
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        setAccessibilityRole(.button)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        let content = NSStackView(views: [icon, label])
        content.spacing = 4
        content.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 9)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        show(rendered: false)
        // A selector observer: removed by itself when the button goes.
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: EditorAppearance.didChange, object: nil)
    }

    @objc private func themeChanged() { restyle() }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("MarkdownToggle is created in code") }

    /// What a press does next: render, or go back to the text.
    func show(rendered: Bool) {
        icon.image = (rendered ? Icon.code : Icon.eye).image(size: 12)
        label.stringValue = rendered ? T("Code", "Código") : T("Preview", "Visualizar")
        HoverTip.attach(rendered ? T("Back to the text (⇧⌘V)", "Voltar para o texto (⇧⌘V)") : T("View rendered Markdown (⇧⌘V)", "Ver o Markdown renderizado (⇧⌘V)"), to: self)
        setAccessibilityLabel(label.stringValue)
        restyle()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    /// The editor's own colors, so the button reads on any theme.
    private func restyle() {
        let look = EditorAppearance.current
        layer?.backgroundColor = look.background.blended(withFraction: 0.12, of: look.foreground)?.cgColor
        layer?.borderColor = look.foreground.withAlphaComponent(0.15).cgColor
        label.textColor = look.foreground
        icon.contentTintColor = look.foreground.withAlphaComponent(0.8)
    }

    override func mouseDown(with event: NSEvent) { onPress?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
