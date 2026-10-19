import Foundation

/// Which lines a patch removed and added (1-based, in the old and the new
/// text), read from its hunk headers: the side-by-side view paints them.
struct DiffLines: Equatable {
    var removed: Set<Int> = []
    var added: Set<Int> = []

    init(patch: String) {
        var old = 0
        var new = 0
        var inHunk = false
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                let numbers = Self.hunkStarts(line)
                old = numbers.old
                new = numbers.new
                inHunk = true
                continue
            }
            guard inHunk, let first = line.first else { continue }
            switch first {
            case " ": old += 1; new += 1
            case "-": removed.insert(old); old += 1
            case "+": added.insert(new); new += 1
            default: break
            }
        }
    }

    /// "@@ -12,3 +12,4 @@" -> (12, 12).
    static func hunkStarts(_ header: Substring) -> (old: Int, new: Int) {
        let parts = header.split(separator: " ")
        func start(_ prefix: Character) -> Int {
            guard let part = parts.first(where: { $0.first == prefix }) else { return 1 }
            return Int(part.dropFirst().split(separator: ",").first ?? "1") ?? 1
        }
        return (start("-"), start("+"))
    }
}
