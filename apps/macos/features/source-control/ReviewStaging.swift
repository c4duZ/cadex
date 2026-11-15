import Foundation

/// From lines the owner marked in the review (a diff against the base) to
/// the lines of the patch git stages from (docs/spec/source-control.md,
/// Stage parcial). The review's new side is the work tree, so is the
/// unstaged patch's: an added line matches by its number. A removed line
/// has no number on the new side: it matches by its text, where it would
/// sit (`anchor`, the new line after it). The staged patch counts lines of
/// the index, not of the disk: unstaging matches by text alone.
enum ReviewStaging {
    /// A marked line: its kind, its text, and its place on the new side
    /// (an added or unchanged line's number; a removed line's anchor).
    struct Marked: Equatable {
        let kind: ReviewLayout.Kind
        let text: String
        let anchor: Int
    }

    /// The patch's line indices (split on "\n") to stage, or to unstage.
    static func indices(of marked: [Marked], in patch: String, unstage: Bool) -> [Int] {
        let changes = marked.filter { $0.kind != .context }
        guard !changes.isEmpty else { return [] }
        let low = changes.map(\.anchor).min() ?? 0
        let high = changes.map(\.anchor).max() ?? 0
        let addedLines = Set(changes.filter { $0.kind == .added }.map(\.anchor))
        var addedTexts = changes.filter { $0.kind == .added }.map(\.text)
        var removedTexts = changes.filter { $0.kind == .removed }.map(\.text)
        var picked: [Int] = []
        var new = 0
        var inHunk = false
        for (index, line) in patch.components(separatedBy: "\n").enumerated() {
            if line.hasPrefix("@@") {
                new = DiffLines.hunkStarts(Substring(line)).new
                if new == 0 { new = 1 }
                inHunk = true
                continue
            }
            guard inHunk, let mark = line.first else { continue }
            let text = String(line.dropFirst())
            switch mark {
            case "+":
                if unstage ? take(text, from: &addedTexts) : addedLines.contains(new) { picked.append(index) }
                new += 1
            case "-":
                let near = (low...max(high, low) + 1).contains(new)
                if (unstage || near), take(text, from: &removedTexts) { picked.append(index) }
            case " ":
                new += 1
            default:
                break
            }
        }
        return picked
    }

    private static func take(_ text: String, from list: inout [String]) -> Bool {
        guard let at = list.firstIndex(of: text) else { return false }
        list.remove(at: at)
        return true
    }

    /// The marked rows of the layout, with their anchors: a removed line's
    /// is the number of the next line on the new side in its file.
    static func marked(_ rows: [ReviewLayout.Row], at indices: [Int], files: [ReviewFileDiff]) -> [Marked] {
        indices.compactMap { index in
            guard rows.indices.contains(index), case .line(let file, let kind, _, let new, _) = rows[index] else { return nil }
            let anchor = new ?? nextNew(after: index, in: rows, file: file, files: files)
            return Marked(kind: kind, text: ReviewLayout.text(of: rows[index], in: files), anchor: anchor)
        }
    }

    private static func nextNew(after index: Int, in rows: [ReviewLayout.Row], file: Int, files: [ReviewFileDiff]) -> Int {
        var at = index + 1
        while at < rows.count, ReviewLayout.file(of: rows[at]) == file {
            if case .line(_, _, _, let new?, _) = rows[at] { return new }
            at += 1
        }
        return files.indices.contains(file) ? files[file].after.count + 1 : 1
    }
}
