import AppKit

/// Folded regions (docs/spec/editor.md): the first line of a fold stays,
/// the lines below it are left out of the layout by TextKit 2's content
/// manager delegate, without touching the text.
@MainActor
final class EditorFolding: NSObject, NSTextContentStorageDelegate {
    /// Foldable regions from the core, by start line.
    private(set) var regions: [Int: EditorSyntax.Fold] = [:]
    /// Start lines of the folded regions.
    private(set) var folded: Set<Int> = []
    /// Lines hidden by the folded regions, and the line starts to find
    /// them: a copy the layout reads, maybe off the main thread, so it is
    /// replaced whole and never mutated in place.
    nonisolated(unsafe) private var snapshot = (hidden: IndexSet(), lines: LineIndex())
    var lines = LineIndex() {
        didSet { snapshot = (snapshot.hidden, lines) }
    }
    /// Called after the hidden lines change: relayout and redraw.
    var onChange: (() -> Void)?

    func setRegions(_ list: [EditorSyntax.Fold]) {
        regions = Dictionary(list.map { ($0.start, $0) }, uniquingKeysWith: { a, _ in a })
        folded = folded.filter { regions[$0] != nil }
        recompute()
    }

    func isFoldStart(_ line: Int) -> Bool { regions[line] != nil }
    func isFolded(_ line: Int) -> Bool { folded.contains(line) }

    func toggle(line: Int) {
        guard regions[line] != nil else { return }
        if folded.contains(line) { folded.remove(line) } else { folded.insert(line) }
        recompute()
    }

    func unfoldAll() {
        guard !folded.isEmpty else { return }
        folded = []
        recompute()
    }

    func foldAll() {
        folded = Set(regions.keys)
        recompute()
    }

    /// The hidden lines again; the layout is redone only when they changed.
    /// Every key sets the regions anew, and redoing the whole layout each
    /// time made the text jump while typing (issue #2, 2026-10-21).
    private func recompute() {
        var set = IndexSet()
        for start in folded {
            guard let region = regions[start], region.end > start else { continue }
            set.insert(integersIn: (start + 1)...region.end)
        }
        let changed = set != snapshot.hidden
        snapshot = (set, lines)
        if changed { onChange?() }
    }

    /// Whether the paragraph starting at `offset` is hidden by a fold.
    nonisolated func hides(offset: Int) -> Bool {
        let current = snapshot
        return !current.hidden.isEmpty && current.hidden.contains(current.lines.line(at: offset))
    }

    nonisolated func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement,
                                        options: NSTextContentManager.EnumerationOptions = []) -> Bool {
        guard let range = textElement.elementRange else { return true }
        let offset = textContentManager.offset(from: textContentManager.documentRange.location, to: range.location)
        return !hides(offset: offset)
    }
}
