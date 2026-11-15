import AppKit

/// What the review tab gives the app for comments (plan 21 phase D), with
/// nothing of the comments themselves: the marked lines with their text and
/// context, each file's two texts to place a comment again, the note under
/// the cursor, and the bar's button.
extension ReviewDocument {
    /// The marked lines (the cursor's alone when none) as a selection.
    public func markedSelection() -> ReviewLineSelection? { selection(of: text.marked) }

    /// One file and one side: the new side when any line has a new number
    /// (unchanged and added), else the old one (removed lines).
    func selection(of rows: [Int]) -> ReviewLineSelection? {
        // A run stays inside its stretch of code: it stops at the first row
        // that is not a line (a fold, a note, the next file's header).
        guard let low = rows.min() else { return nil }
        var run: [Int] = []
        for index in low...(rows.max() ?? low) {
            guard text.layout.rows.indices.contains(index), case .line = text.layout.rows[index] else { break }
            run.append(index)
        }
        let lines = run.compactMap { index -> (file: Int, kind: ReviewLayout.Kind, old: Int?, new: Int?)? in
            guard text.layout.rows.indices.contains(index), case .line(let file, let kind, let old, let new, _) = text.layout.rows[index] else { return nil }
            return (file, kind, old, new)
        }
        guard let first = lines.first, files.indices.contains(first.file) else { return nil }
        let same = lines.filter { $0.file == first.file }
        let old = same.allSatisfy { $0.new == nil }
        let numbers = same.compactMap { old ? $0.old : $0.new }
        guard let start = numbers.min(), let end = numbers.max() else { return nil }
        let source = old ? files[first.file].before : files[first.file].after
        func slice(_ from: Int, _ to: Int) -> [String] {
            let low = max(from, 1), high = min(to, source.count)
            return low <= high ? Array(source[(low - 1)...(high - 1)]) : []
        }
        return ReviewLineSelection(path: files[first.file].file.path, old: old, start: start, end: end,
                                   lines: slice(start, end), before: slice(start - 3, start - 1), after: slice(end + 1, end + 3))
    }

    /// A file's text before and after, to place a comment again; nil when
    /// the file is not in the review any more.
    public func texts(of path: String) -> (before: [String], after: [String])? {
        files.first { $0.file.path == path }.map { ($0.before, $0.after) }
    }

    /// The files in the review, in order.
    public var paths: [String] { files.map(\.file.path) }

    /// The note the cursor is on, if any.
    public var cursorAnnotation: String? {
        guard text.layout.rows.indices.contains(text.cursor), case .annotation(_, let index) = text.layout.rows[text.cursor],
              text.layout.annotations.indices.contains(index) else { return nil }
        return text.layout.annotations[index].id
    }

    /// Where to anchor a popover for the marked lines (or a note): the
    /// review's text view and the cursor row's rect in it.
    public var anchor: (view: NSView, rect: NSRect)? {
        guard text.layout.rows.indices.contains(text.cursor) else { return nil }
        return (text, text.rect(of: text.cursor))
    }

    /// A message on the bar, before the summary (the app's: sent, copied).
    public func announce(_ message: String) {
        notice = message
        say(bar.stringValue.components(separatedBy: " — ").last ?? "")
    }

    func showBarAction() {
        barButton.isHidden = barAction == nil
        barButton.title = barAction?.title ?? ""
        barButton.onPress = { [weak self] in self?.barAction?.run() }
    }
}
