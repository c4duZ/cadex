import Foundation

/// Where each line starts, in UTF-16 units: line numbers for the ruler and
/// line ranges for recoloring and folds. Rebuilt after each edit; a scan of
/// the text is cheap next to laying it out.
struct LineIndex: Equatable {
    /// starts[i] is the offset of line i; starts[0] is 0.
    private(set) var starts: [Int] = [0]
    private(set) var length = 0

    init(_ text: NSString = "") {
        rebuild(text)
    }

    mutating func rebuild(_ text: NSString) {
        var list = [0]
        let count = text.length
        var buffer = [unichar](repeating: 0, count: 4096)
        var at = 0
        while at < count {
            let n = min(buffer.count, count - at)
            text.getCharacters(&buffer, range: NSRange(location: at, length: n))
            for i in 0..<n where buffer[i] == 0x0A {
                list.append(at + i + 1)
            }
            at += n
        }
        starts = list
        length = count
    }

    var count: Int { starts.count }

    /// The 0-based line holding `offset`.
    func line(at offset: Int) -> Int {
        var lo = 0
        var hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// Lines [first, last] as a range of the text, line breaks included.
    func range(lines first: Int, through last: Int) -> NSRange {
        let start = starts[max(0, min(first, starts.count - 1))]
        let end = last + 1 < starts.count ? starts[last + 1] : length
        return NSRange(location: start, length: max(0, end - start))
    }

    /// `range` grown to whole lines.
    func wholeLines(_ range: NSRange) -> NSRange {
        let first = line(at: range.location)
        let last = line(at: max(range.location, NSMaxRange(range) - 1))
        return self.range(lines: first, through: last)
    }
}
