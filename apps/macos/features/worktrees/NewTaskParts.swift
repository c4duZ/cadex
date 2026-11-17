import AppKit
import Strings
import UILooks

/// The pieces of the New Task sheet as the NewTask mockup draws them (components.newTask): a
/// "WHERE" option, an agent's row and a line of note. NewTaskSheet lays them out.
typealias NT = DesignTokens.NewTask

@MainActor
func newTaskLabel(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular, tracking: CGFloat = 0) -> NSTextField {
    let label = NSTextField(labelWithString: "")
    label.attributedStringValue = NSAttributedString(string: text, attributes: [
        .font: UILooks.font(size, weight: weight), .foregroundColor: color, .kern: UILooks.pt(size) * tracking,
    ])
    label.lineBreakMode = .byTruncatingTail
    return label
}

/// A box that runs `onPress` on a click.
@MainActor
class NewTaskClickable: NSView {
    var onPress: (() -> Void)?
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { if onPress != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }

    func box(bg: NSColor?, border: NSColor?, radius: CGFloat) {
        wantsLayer = true
        layer?.backgroundColor = bg?.cgColor
        layer?.borderColor = border?.cgColor
        layer?.borderWidth = border == nil ? 0 : DesignTokens.Stroke.hairline
        layer?.cornerRadius = UILooks.pt(radius)
    }

    /// Its content inside the padding.
    func hold(_ content: NSView, padding: NSEdgeInsets) {
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

/// "○ In the project's folder" / "● Separate copy · branch cache-evict" with its sentence; the
/// chosen one with the working blue line and tint. The copy's branch is a field in its title.
@MainActor
final class NewTaskOption: NewTaskClickable {
    private let title = NSTextField(labelWithString: "")
    let branch = NSTextField()
    private let titleText: String

    init(title: String, note: String, withBranch: Bool) {
        titleText = title
        super.init(frame: .zero)
        let bold = UILooks.font(DesignTokens.FontSize.body, weight: DesignTokens.FontWeight.semibold)
        self.title.font = bold
        self.title.textColor = DesignTokens.Color.textPrimary
        var head: [NSView] = [self.title]
        if withBranch {
            branch.isBordered = false
            branch.drawsBackground = false
            branch.focusRingType = .none
            branch.font = bold
            branch.textColor = DesignTokens.Color.textPrimary
            branch.setContentHuggingPriority(.init(1), for: .horizontal)
            branch.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            head.append(branch)
        }
        let headRow = NSStackView(views: head)
        headRow.spacing = 0
        let sentence = newTaskLabel(note, size: NT.Option.Note.fontSize, color: NT.Option.Note.color)
        let column = NSStackView(views: [headRow, sentence])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = UILooks.pt(NT.Option.textGap)
        hold(column, padding: NT.Option.padding)
        headRow.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NewTaskOption is created in code") }

    func show(chosen: Bool, enabled: Bool) {
        title.stringValue = (chosen ? "● " : "○ ") + titleText
        box(bg: chosen ? NT.Option.Selected.bg : nil, border: chosen ? NT.Option.Selected.border : NT.Option.border, radius: NT.Option.radius)
        alphaValue = enabled ? 1 : DesignTokens.Opacity.paneIdle / 2
        setAccessibilityValue(chosen)
    }
}

/// "1  Claude Opus · bkdg   84% used  ✕": a click on the name opens the agent's menu.
@MainActor
final class NewTaskAgentRow: NewTaskClickable {
    let remove = NSButton(title: "✕", target: nil, action: nil)

    init(index: Int, agent: NewTaskAgent) {
        super.init(frame: .zero)
        typealias R = NT.AgentRow
        box(bg: R.bg, border: nil, radius: R.radius)
        let number = newTaskLabel("\(index)", size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary, weight: DesignTokens.FontWeight.semibold)
        let name = newTaskLabel(agent.title + " ▾", size: DesignTokens.FontSize.body, color: DesignTokens.Color.textPrimary)
        name.setContentHuggingPriority(.init(1), for: .horizontal)
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let usage = newTaskLabel(agent.usage, size: R.Usage.fontSize, color: R.Usage.color)
        remove.isBordered = false
        remove.attributedTitle = NSAttributedString(string: "✕", attributes: [.font: UILooks.font(R.Usage.fontSize), .foregroundColor: R.remove])
        remove.setAccessibilityLabel(T("Remove this agent", "Tirar este agente"))
        let row = NSStackView(views: [number, name, usage, remove])
        row.spacing = UILooks.pt(R.gap)
        row.distribution = .fill
        hold(row, padding: R.padding)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(agent.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("NewTaskAgentRow is created in code") }
}

/// What used to be a question before the task (the folder, new setup hooks, the trust): a line
/// of the sheet, with an action when there is one ("Choose Another Folder…").
public struct NewTaskNote: Sendable {
    public var text: String
    public var action: String?
    public var run: (@MainActor @Sendable () -> Void)?
    /// Start cannot run while this line stands (an account that does not trust the folder yet).
    public var blocks: Bool

    public init(_ text: String, action: String? = nil, blocks: Bool = false, run: (@MainActor @Sendable () -> Void)? = nil) {
        self.text = text
        self.action = action
        self.blocks = blocks
        self.run = run
    }
}
