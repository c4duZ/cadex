import AppKit

/// Keeps the core's syntax tree in step with the text and paints its spans
/// as foreground colors. After an edit only the lines the core reports as
/// changed are painted again (docs/spec/editor.md: no recoloring the whole
/// file per key).
@MainActor
final class EditorHighlighter: NSObject, NSTextStorageDelegate {
    private(set) var syntax: EditorSyntax?
    private(set) var lines = LineIndex()
    var appearance: EditorAppearance
    /// The text changed (characters, not colors): line starts are current.
    var onTextChange: (() -> Void)?
    private weak var storage: NSTextStorage?
    private var pending: NSRange?

    init(storage: NSTextStorage, fileName: String, appearance: EditorAppearance, highlight: Bool) {
        self.storage = storage
        self.appearance = appearance
        super.init()
        lines = LineIndex(storage.string as NSString)
        if highlight { syntax = EditorSyntax(fileName: fileName, text: storage.string) }
        storage.delegate = self
    }

    var language: String? { syntax?.language }

    /// Font and colors over the whole text: on open and when the theme
    /// changes.
    func paintAll() {
        guard let storage else { return }
        let all = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttributes([.font: appearance.font, .foregroundColor: appearance.foreground], range: all)
        paintSpans(in: all, storage: storage)
        storage.endEditing()
    }

    private func paint(_ range: NSRange) {
        guard let storage else { return }
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        guard clamped.length > 0 || storage.length == 0 else { return }
        let target = lines.wholeLines(clamped)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: appearance.foreground, range: target)
        paintSpans(in: target, storage: storage)
        storage.endEditing()
    }

    private func paintSpans(in range: NSRange, storage: NSTextStorage) {
        guard let syntax else { return }
        for span in syntax.spans(in: range) {
            guard let color = appearance.tokens[span.kind], NSMaxRange(span.range) <= storage.length else { continue }
            storage.addAttribute(.foregroundColor, value: color, range: span.range)
        }
    }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Text views edit their storage on the main thread.
        nonisolated(unsafe) let storage = textStorage
        MainActor.assumeIsolated { textChanged(storage, editedRange, delta) }
    }

    private func textChanged(_ storage: NSTextStorage, _ editedRange: NSRange, _ delta: Int) {
        let oldRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        let replacement = (storage.string as NSString).substring(with: editedRange)
        lines.rebuild(storage.string as NSString)
        if let syntax {
            let changed = syntax.edit(oldRange, replacement: replacement)
            schedulePaint(NSUnionRange(changed, editedRange))
        }
        onTextChange?()
    }

    /// Colors change after the edit is processed: changing attributes from
    /// inside processEditing would start another edit.
    private func schedulePaint(_ range: NSRange) {
        let first = pending == nil
        pending = pending.map { NSUnionRange($0, range) } ?? range
        guard first else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let range = self.pending else { return }
            self.pending = nil
            self.paint(range)
        }
    }

    func folds() -> [EditorSyntax.Fold] {
        syntax?.folds() ?? []
    }
}
