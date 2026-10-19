import AppKit
import Icons

/// The gutter left of the code: line numbers and, on lines that start a
/// foldable block, the arrow that folds it (docs/spec/editor.md). Reads the
/// layout from TextKit 2; it never touches the old layout manager, which
/// would switch the text view back to TextKit 1.
final class LineRuler: NSRulerView {
    weak var folding: EditorFolding?
    var numberColor: NSColor = .tertiaryLabelColor { didSet { needsDisplay = true } }
    var background: NSColor = .textBackgroundColor { didSet { needsDisplay = true } }
    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) { didSet { updateThickness() } }
    private static let arrowWidth: CGFloat = 14

    init(textView: NSTextView, scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("LineRuler is created in code") }

    private var textView: NSTextView? { clientView as? NSTextView }

    /// Wide enough for the biggest line number and the fold arrow.
    func updateThickness() {
        let lines = folding?.lines.count ?? 1
        let digits = max(3, String(lines).count)
        let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
        ruleThickness = ceil(CGFloat(digits) * digit + Self.arrowWidth + 10)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        background.setFill()
        bounds.fill()
        guard let textView, let layout = textView.textLayoutManager, let storage = layout.textContentManager,
              let folding else { return }
        let visible = textView.visibleRect
        let start = layout.textLayoutFragment(for: CGPoint(x: 0, y: visible.minY))?.rangeInElement.location
            ?? layout.documentRange.location
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
        let numberRight = ruleThickness - Self.arrowWidth - 4
        layout.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame
            if frame.minY > visible.maxY { return false }
            let offset = storage.offset(from: storage.documentRange.location, to: fragment.rangeInElement.location)
            let line = folding.lines.line(at: offset)
            let y = self.convert(NSPoint(x: 0, y: frame.minY + textView.textContainerOrigin.y), from: textView).y
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let lineHeight = fragment.textLineFragments.first?.typographicBounds.height ?? frame.height
            label.draw(at: NSPoint(x: numberRight - size.width, y: y + (lineHeight - size.height) / 2), withAttributes: attributes)
            if folding.isFoldStart(line) {
                self.drawArrow(folded: folding.isFolded(line), y: y, lineHeight: lineHeight)
            }
            return true
        }
    }

    private func drawArrow(folded: Bool, y: CGFloat, lineHeight: CGFloat) {
        let size: CGFloat = 11
        let icon = (folded ? Icon.caretRight : Icon.caretDown).image(size: size)
        let tinted = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            self.numberColor.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: ruleThickness - Self.arrowWidth, y: y + (lineHeight - size) / 2, width: size, height: size))
    }

    /// A click on a fold arrow folds or unfolds that block.
    override func mouseDown(with event: NSEvent) {
        guard let textView, let layout = textView.textLayoutManager, let storage = layout.textContentManager,
              let folding else { return }
        let point = convert(event.locationInWindow, from: nil)
        let inText = textView.convert(point, from: self)
        let y = inText.y - textView.textContainerOrigin.y
        guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return }
        let offset = storage.offset(from: storage.documentRange.location, to: fragment.rangeInElement.location)
        folding.toggle(line: folding.lines.line(at: offset))
    }

    override var isFlipped: Bool { true }
}
