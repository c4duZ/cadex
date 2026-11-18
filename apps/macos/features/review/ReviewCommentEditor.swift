import AppKit
import UILooks
import Strings

/// The field where a comment is written (docs/spec/review.md): a popover
/// under the lines, Markdown as plain text, ⌘Enter saves, Esc gives up.
@MainActor
public final class ReviewCommentEditor: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let field = CommentTextView()
    private var save: ((String) -> Void)?
    private static var current: ReviewCommentEditor?

    /// Shows the field at `rect` of `view`, with `text` already in it.
    public static func show(at rect: NSRect, of view: NSView, title: String, text: String = "", save: @escaping (String) -> Void) {
        let editor = ReviewCommentEditor()
        current = editor
        editor.save = save
        editor.open(at: rect, of: view, title: title, text: text)
    }

    private func open(at rect: NSRect, of view: NSView, title: String, text: String) {
        let label = NSTextField(labelWithString: title)
        label.font = UILooks.font(DesignTokens.FontSize.caption, weight: DesignTokens.FontWeight.semibold)
        label.textColor = DesignTokens.Color.textSecondary
        let hint = NSTextField(labelWithString: T("Markdown · ⌘↩ saves · esc gives up", "Markdown · ⌘↩ salva · esc desiste"))
        hint.font = UILooks.font(DesignTokens.FontSize.chip)
        hint.textColor = DesignTokens.Color.textTertiary
        let scroll = NSScrollView()
        scroll.documentView = field
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = DesignTokens.NewTask.Field.bg.cgColor
        scroll.layer?.borderColor = DesignTokens.NewTask.Field.border.cgColor
        scroll.layer?.borderWidth = DesignTokens.Stroke.hairline
        scroll.layer?.cornerRadius = UILooks.pt(DesignTokens.NewTask.Field.radius)
        field.isRichText = false
        field.font = UILooks.font(DesignTokens.FontSize.body)
        field.textColor = DesignTokens.Color.textPrimary
        field.insertionPointColor = DesignTokens.Color.textPrimary
        field.drawsBackground = false
        field.string = text
        field.minSize = NSSize(width: 0, height: 90)
        field.maxSize = NSSize(width: 10_000, height: 10_000)
        field.isVerticallyResizable = true
        field.autoresizingMask = [.width]
        field.onSave = { [weak self] in self?.finish(save: true) }
        field.onCancel = { [weak self] in self?.finish(save: false) }
        let stack = NSStackView(views: [label, scroll, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 8, right: 10)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: 380), scroll.heightAnchor.constraint(equalToConstant: 110)])
        let controller = NSViewController()
        controller.view = stack
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.makeFirstResponder(field)
    }

    private func finish(save: Bool) {
        let text = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let handler = self.save
        self.save = nil
        popover.close()
        if save, !text.isEmpty { handler?(text) }
    }

    public func popoverDidClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }
}

/// ⌘Enter and Esc for the comment field.
@MainActor
final class CommentTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command) { return onSave?() ?? () }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
