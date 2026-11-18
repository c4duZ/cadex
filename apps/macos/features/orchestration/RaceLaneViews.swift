import AppKit
import Strings
import UILooks

/// The pieces of a race's tab (plan 30 B; the Race mockup): the strip over the lanes with the
/// prompt, where the contenders started and the cap, and Compare…; and each lane's foot with
/// Review and Pick winner. The lanes themselves are the contenders' terminals side by side.
public enum RaceLaneViews {
    /// "“Make the cache evict by age”  from main · cap US$ 1.00, 20 min each        Compare…".
    @MainActor
    public static func banner(prompt: String, base: String, budget: Double, minutes: Int, compare: @escaping @MainActor () -> Void) -> NSView {
        typealias B = DesignTokens.Race.Banner
        let quote = NSTextField(labelWithString: "“" + (prompt.split(separator: "\n").first.map(String.init) ?? "") + "”")
        quote.font = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.semibold)
        quote.textColor = DesignTokens.Color.textPrimary
        quote.lineBreakMode = .byTruncatingTail
        quote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let meta = NSTextField(labelWithString: T("from \(base) · cap US$ \(String(format: "%.2f", budget)), \(minutes) min each",
                                                  "de \(base) · teto US$ \(String(format: "%.2f", budget)), \(minutes) min cada"))
        meta.font = UILooks.font(DesignTokens.FontSize.body)
        meta.textColor = B.meta
        meta.lineBreakMode = .byTruncatingTail
        meta.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let button = DesignButton.make(T("Compare…", "Comparar…"), .secondary, action: compare)
        let row = NSStackView(views: [quote, meta, spacer, button])
        row.spacing = UILooks.pt(B.gap)
        let pad = B.padding
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: UILooks.pt(pad.bottom), right: UILooks.pt(pad.right))
        row.wantsLayer = true
        row.layer?.backgroundColor = B.bg.cgColor
        return row
    }

    /// A lane's foot: Review and Pick winner, on the box's bottom with a line above.
    @MainActor
    public static func foot(review: @escaping @MainActor () -> Void, pickWinner: @escaping @MainActor () -> Void) -> NSView {
        typealias F = DesignTokens.Race.Lane.Footer
        let row = NSStackView(views: [DesignButton.make(T("Review", "Revisar"), .secondary, action: review),
                                      DesignButton.make(T("Pick winner", "Escolher vencedora"), .primary, action: pickWinner)])
        row.spacing = UILooks.pt(F.gap)
        let pad = F.padding
        row.edgeInsets = NSEdgeInsets(top: UILooks.pt(pad.top), left: UILooks.pt(pad.left), bottom: UILooks.pt(pad.bottom), right: UILooks.pt(pad.right))
        let box = LaneFoot()
        box.wantsLayer = true
        box.layer?.backgroundColor = F.bg.cgColor
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = F.borderTop.cgColor
        for view in [line, row] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(view)
        }
        NSLayoutConstraint.activate([
            line.topAnchor.constraint(equalTo: box.topAnchor), line.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: box.trailingAnchor), line.heightAnchor.constraint(equalToConstant: DesignTokens.Stroke.hairline),
            row.topAnchor.constraint(equalTo: line.bottomAnchor), row.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor), row.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        return box
    }
}

/// The lane's foot keeps the box's rounded bottom corners.
final class LaneFoot: NSView {
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        layer?.cornerRadius = UILooks.pt(DesignTokens.Pane.radius) - DesignTokens.Stroke.hairline
        layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }
}
