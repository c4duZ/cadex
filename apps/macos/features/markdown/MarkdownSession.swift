import AppKit
import Editor

/// Markdown help for one note open in the editor (docs/spec/markdown.md):
/// broken links underlined, ⌘+click follows a link, and suggestions while
/// writing `](`, `](file#` and `[[`. Talks to the editor through its entry
/// point only (the text view and the ⌘+click hook).
@MainActor
final class MarkdownSession: NSObject, NSTextViewDelegate {
    let path: String
    private weak var document: EditorDocument?
    private unowned let controller: MarkdownController
    private(set) var links: [MarkdownIndex.Link] = []
    private let popup = CompletionPopup()
    private var trigger: CompletionTrigger?
    private var refreshPending = false

    init(document: EditorDocument, controller: MarkdownController) {
        self.document = document
        self.controller = controller
        path = document.path
        super.init()
        document.textView?.delegate = self
        document.commandClick = { [weak self] index in self?.follow(at: index) ?? false }
        popup.onChoose = { [weak self] item in self?.insert(item) }
        refreshLinks()
    }

    private var textView: NSTextView? { document?.textView }

    /// Path relative to the workspace root.
    var relativePath: String {
        path.hasPrefix(controller.root + "/") ? String(path.dropFirst(controller.root.count + 1)) : path
    }

    // MARK: Links

    func textDidChange(_ notification: Notification) {
        scheduleRefresh()
        updateCompletion()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if popup.isVisible { updateCompletion() }
    }

    /// Links are checked a moment after typing stops, not per key.
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshPending = false
            self?.refreshLinks()
        }
    }

    func refreshLinks() {
        guard let textView else { return }
        links = controller.index.links(in: textView.string, of: path)
        underlineBroken(in: textView)
    }

    /// Broken links get a dotted red underline, as attributes of the text:
    /// TextKit 2's rendering attributes were dropped each time the editor
    /// painted its colors again (2026-10-19). Recomputed on every check.
    private func underlineBroken(in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: all)
        storage.removeAttribute(.underlineColor, range: all)
        for link in links where link.broken && NSMaxRange(link.range) <= storage.length {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle([.single, .patternDot]).rawValue, range: link.range)
            storage.addAttribute(.underlineColor, value: NSColor.systemRed, range: link.range)
        }
        storage.endEditing()
    }

    /// The link at a character offset, if any.
    func link(at index: Int) -> MarkdownIndex.Link? {
        links.first { NSLocationInRange(index, $0.range) || NSMaxRange($0.range) == index }
    }

    /// ⌘+click, and markdown.open-link at the cursor.
    @discardableResult
    func follow(at index: Int) -> Bool {
        refreshLinks()
        guard let link = link(at: index) else { return false }
        controller.follow(link)
        return true
    }

    // MARK: Completion

    private func updateCompletion() {
        guard let textView, let window = textView.window else { return popup.hide() }
        let cursor = textView.selectedRange()
        guard cursor.length == 0, let found = CompletionTrigger.detect(in: textView.string as NSString, cursor: cursor.location) else {
            trigger = nil
            return popup.hide()
        }
        trigger = found
        let items = controller.suggestions(for: found, from: relativePath)
        let caret = textView.firstRect(forCharacterRange: cursor, actualRange: nil)
        popup.show(items, below: caret, in: window)
    }

    private func insert(_ item: CompletionPopup.Item) {
        guard let textView, let trigger else { return }
        popup.hide()
        let range = trigger.range
        guard textView.shouldChangeText(in: range, replacementString: item.insert) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: item.insert)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(location: range.location + (item.insert as NSString).length, length: 0))
        self.trigger = nil
        popup.hide()
    }

    /// ↑ ↓ Enter Tab Esc steer the suggestions while they show.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard popup.isVisible else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)): popup.move(-1)
        case #selector(NSResponder.moveDown(_:)): popup.move(1)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)): popup.chooseSelected()
        case #selector(NSResponder.cancelOperation(_:)): popup.hide()
        default: return false
        }
        return true
    }

    func close() {
        popup.hide()
    }
}
