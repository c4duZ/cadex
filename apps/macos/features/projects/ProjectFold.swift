import AppKit
import Icons
import Strings
import UILooks

/// A part of a line's detail that starts closed: a caret and a title that open plain text under
/// them (plan 35 H: the briefing a session received, secondary to its summary). The text is the
/// app's as given, selectable, in the monospaced font, since it is what an agent read.
@MainActor
final class ProjectFold: NSStackView {
    private let caret = NSImageView()
    private let body: NSTextField
    private(set) var isOpen = false

    init(_ fold: PageDetail.Fold) {
        body = NSTextField(wrappingLabelWithString: fold.text)
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = UILooks.pt(6)
        caret.contentTintColor = DesignTokens.Color.textTertiary
        let title = pageLabel(fold.title.uppercased(), size: DesignTokens.FontSize.caption, color: DesignTokens.Color.textTertiary,
                              weight: .bold, tracking: 0.06)
        let line = NSStackView(views: [caret, title])
        line.spacing = UILooks.pt(4)
        let head = PageBox()
        head.hold(line, padding: NSEdgeInsets())
        head.onPress = { [weak self] in self?.toggle() }
        head.setAccessibilityElement(true)
        head.setAccessibilityRole(.disclosureTriangle)
        head.setAccessibilityLabel(fold.title)
        body.font = fold.plain ? UILooks.font(DesignTokens.FontSize.meta) : UILooks.monospaced(DesignTokens.FontSize.small)
        body.textColor = fold.plain ? DesignTokens.Color.textTertiary : DesignTokens.Color.textRow
        body.isSelectable = true
        body.maximumNumberOfLines = 0
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addArrangedSubview(head)
        addArrangedSubview(body)
        body.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        show(open: false)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("ProjectFold is created in code") }

    func toggle() { show(open: !isOpen) }

    private func show(open: Bool) {
        isOpen = open
        caret.image = (open ? Icon.caretDown : Icon.caretRight).image(size: UILooks.pt(10))
        body.isHidden = !open
    }
}
