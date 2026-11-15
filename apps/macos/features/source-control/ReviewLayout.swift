import Foundation

/// One file of the review with what the core gave for it: the base's text,
/// the work tree's (or the other tip's) and the patch between them.
struct ReviewFileDiff: Sendable {
    let file: GitRepository.ReviewFile
    let before: [String]
    let after: [String]
    let patch: String
    let binary: Bool
    let tooLarge: Bool
    /// An image's two versions (plan 21 phase C); nil for the rest.
    var beforeData: Data?
    var afterData: Data?

    /// An image both of whose sides are small enough to compare.
    var showsImage: Bool {
        (beforeData != nil || afterData != nil)
            && (beforeData?.count ?? 0) <= ImageDiffView.maxBytes && (afterData?.count ?? 0) <= ImageDiffView.maxBytes
    }

    init(file: GitRepository.ReviewFile, diff: GitRepository.Diff?) {
        self.file = file
        before = Self.lines(diff?.before ?? "")
        after = Self.lines(diff?.after ?? "")
        patch = diff?.patch ?? ""
        binary = diff?.binary ?? false
        tooLarge = diff?.tooLarge ?? false
    }

    static func lines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }
}

/// The review's rows, stacked file after file (docs/spec/review.md): a
/// header per file, then its lines with the old and new numbers, unchanged
/// runs folded beyond the context lines, and where each file and each
/// change starts, for j/k and n/p. Pure: the view draws only what shows.
struct ReviewLayout: Equatable {
    enum Kind: Equatable, Sendable { case context, added, removed }

    enum Row: Equatable, Sendable {
        case header(file: Int)
        /// `change`: the run of changed lines it belongs to (nil: unchanged).
        case line(file: Int, kind: Kind, old: Int?, new: Int?, change: Int?)
        /// Unchanged lines hidden; `region` names it for "show more".
        case fold(file: Int, region: Int, count: Int)
        case note(file: Int, text: String)
        /// A changed image, drawn by an ImageDiffView over the row.
        case image(file: Int)
        /// An annotation (a comment) under its line: `index` into `annotations`.
        case annotation(file: Int, index: Int)
    }

    struct Options: Equatable {
        var context = 3
        /// Every line shows (git.review-toggle-collapse).
        var showAll = false
        /// Folds opened one by one: "file:region".
        var opened: Set<String> = []
    }

    private(set) var rows: [Row] = []
    private(set) var fileStarts: [Int] = []
    private(set) var changeStarts: [Int] = []

    /// The notes the app pins (comments, plan 21 phase D), by index in rows.
    private(set) var annotations: [ReviewAnnotation] = []

    init(files: [ReviewFileDiff], options: Options, annotations: [ReviewAnnotation] = [], notes: (ReviewFileDiff) -> String?) {
        self.annotations = annotations
        var change = 0
        for (index, diff) in files.enumerated() {
            fileStarts.append(rows.count)
            var mine: [Row] = [.header(file: index)]
            if diff.showsImage {
                mine.append(.image(file: index))
            } else if let note = notes(diff) {
                mine.append(.note(file: index, text: note))
            } else {
                // An unchanged run holding a commented line stays open.
                var keep = options
                let pinned = annotations.filter { $0.path == diff.file.path && !$0.stale }
                mine += Self.lines(of: diff, file: index, options: &keep, pinned: pinned, change: &change)
            }
            for row in Self.annotationRows(for: index, path: diff.file.path, rows: mine, annotations: annotations) {
                if case .line(_, _, _, _, let id?) = row, rows.last.map({ Self.change(of: $0) != id }) ?? true { changeStarts.append(rows.count) }
                rows.append(row)
            }
        }
    }

    private static func change(of row: Row) -> Int? {
        if case .line(_, _, _, _, let id) = row { return id }
        return nil
    }

    private static func lines(of diff: ReviewFileDiff, file index: Int, options: inout Options, pinned: [ReviewAnnotation], change: inout Int) -> [Row] {
        var rows: [Row] = []
        let items = Self.align(diff)
        var region = 0
        var at = 0
        while at < items.count {
            let item = items[at]
            if item.kind != .context {
                if at == 0 || items[at - 1].kind == .context { change += 1 }
                rows.append(.line(file: index, kind: item.kind, old: item.old, new: item.new, change: change - 1))
                at += 1
                continue
            }
            var end = at
            while end < items.count, items[end].kind == .context { end += 1 }
            let run = Array(items[at..<end])
            if run.contains(where: { item in pinned.contains { $0.old ? $0.line == item.old : $0.line == item.new } }) {
                options.opened.insert("\(index):\(region)")
            }
            rows += Self.unchanged(run, file: index, region: region, first: at == 0, last: end == items.count, options: options)
            region += 1
            at = end
        }
        return rows
    }

    /// The unchanged run between two changes (or at a file's edge): the
    /// context lines next to changes, the middle folded unless opened.
    private static func unchanged(_ run: [Item], file: Int, region: Int, first: Bool, last: Bool, options: Options) -> [Row] {
        func row(_ item: Item) -> Row { .line(file: file, kind: .context, old: item.old, new: item.new, change: nil) }
        let keepBefore = first ? 0 : options.context
        let keepAfter = last ? 0 : options.context
        let hidden = run.count - keepBefore - keepAfter
        if options.showAll || options.opened.contains("\(file):\(region)") || hidden <= 1 { return run.map(row) }
        return run.prefix(keepBefore).map(row) + [.fold(file: file, region: region, count: hidden)] + run.suffix(keepAfter).map(row)
    }

    struct Item: Equatable {
        let kind: Kind
        let old: Int?
        let new: Int?
    }

    /// Every line of the file, unchanged ones included, in order, from the
    /// patch's hunks and the two texts.
    static func align(_ diff: ReviewFileDiff) -> [Item] {
        var items: [Item] = []
        var old = 1
        var new = 1
        func unchanged(until oldStop: Int) {
            while old < oldStop, new <= diff.after.count {
                items.append(Item(kind: .context, old: old, new: new))
                old += 1
                new += 1
            }
        }
        var inHunk = false
        for line in diff.patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                let starts = DiffLines.hunkStarts(line)
                // -0,0 is a new file: nothing comes before its first line.
                if starts.old > 0 { unchanged(until: starts.old) }
                old = max(starts.old, 1)
                new = max(starts.new, 1)
                inHunk = true
                continue
            }
            // Before the first hunk: "diff --git", "--- a/x", "+++ b/x".
            guard inHunk, let mark = line.first, items.count < 200_000 else { continue }
            switch mark {
            case " ": items.append(Item(kind: .context, old: old, new: new)); old += 1; new += 1
            case "-": items.append(Item(kind: .removed, old: old, new: nil)); old += 1
            case "+": items.append(Item(kind: .added, old: nil, new: new)); new += 1
            default: break  // "\ No newline at end of file"
            }
        }
        unchanged(until: diff.before.count + 1)
        return items
    }

    /// The text of a line row.
    static func text(of row: Row, in files: [ReviewFileDiff]) -> String {
        guard case .line(let file, let kind, let old, let new, _) = row, files.indices.contains(file) else { return "" }
        let diff = files[file]
        if kind == .removed, let old, diff.before.indices.contains(old - 1) { return diff.before[old - 1] }
        if let new, diff.after.indices.contains(new - 1) { return diff.after[new - 1] }
        if let old, diff.before.indices.contains(old - 1) { return diff.before[old - 1] }
        return ""
    }

    /// The file a row belongs to.
    static func file(of row: Row) -> Int {
        switch row {
        case .header(let file), .line(let file, _, _, _, _), .fold(let file, _, _), .note(let file, _), .image(let file), .annotation(let file, _): file
        }
    }
}
