import Foundation

/// An image tag on screen: "[Image #N]", which agents such as Claude Code
/// show in place of a pasted image's path (docs/spec/terminal.md, Ver a
/// imagem colada).
struct PastedImageTag: Equatable {
    var number: Int
    var row: Int
    /// First and last cell of the tag, brackets included.
    var firstCol: Int
    var lastCol: Int

    /// The tags in one screen row, given as one string per cell (empty for
    /// the second half of a wide character, so columns stay true).
    static func find(inRow cells: [String], row: Int) -> [PastedImageTag] {
        let prefix = Array("[Image #")
        var tags: [PastedImageTag] = []
        var col = 0
        while col + prefix.count < cells.count {
            guard (0..<prefix.count).allSatisfy({ cells[col + $0] == String(prefix[$0]) }) else {
                col += 1
                continue
            }
            var end = col + prefix.count
            var digits = ""
            while end < cells.count, cells[end].count == 1, let digit = cells[end].first, digit.isASCII, digit.isNumber {
                digits.append(digit)
                end += 1
            }
            if let number = Int(digits), end < cells.count, cells[end] == "]" {
                tags.append(PastedImageTag(number: number, row: row, firstCol: col, lastCol: end))
                col = end + 1
            } else {
                col += 1
            }
        }
        return tags
    }

    /// How many times each number shows, to tell a new tag from old ones.
    static func counts(_ tags: [PastedImageTag]) -> [Int: Int] {
        tags.reduce(into: [:]) { $0[$1.number, default: 0] += 1 }
    }
}

/// Which pasted file each tag number stands for, in one terminal. A paste
/// waits for the first tag number that shows up more often than it did
/// when the paste began; that number becomes the file.
struct PastedImageLinks {
    /// How long a paste waits for its tag: a shell keeps the path as text
    /// and never shows one. Was 5 s; Claude Code came to take almost 8 s to
    /// show "[Image #1]" for a screenshot, and the tag stayed plain text (log
    /// of the owner's run, 2026-10-21).
    static let wait: TimeInterval = 30

    private var pending: [(file: URL, deadline: Date)] = []
    /// Tag counts on screen when the first pending paste began.
    private var baseline: [Int: Int] = [:]
    private(set) var files: [Int: URL] = [:]
    /// The newest paste, tagged or not, for the "last pasted image" commands.
    private(set) var latest: URL?

    var isWaiting: Bool { !pending.isEmpty }

    mutating func pasted(_ file: URL, visible: [Int: Int], now: Date = Date()) {
        if pending.isEmpty { baseline = visible }
        pending.append((file, now.addingTimeInterval(Self.wait)))
        latest = file
    }

    /// The screen changed: new tag numbers take the waiting files, oldest
    /// paste first, lowest number first.
    mutating func screenChanged(visible: [Int: Int], now: Date = Date()) {
        pending.removeAll { $0.deadline < now }
        let new = visible.keys.filter { visible[$0, default: 0] > baseline[$0, default: 0] }.sorted()
        for number in new where !pending.isEmpty {
            files[number] = pending.removeFirst().file
            baseline[number] = visible[number]
        }
    }

    func file(for number: Int) -> URL? { files[number] }
}
