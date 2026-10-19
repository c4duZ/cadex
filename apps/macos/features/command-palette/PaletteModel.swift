import CCadex
import Foundation

/// One row of the palette.
struct PaletteItem: Equatable {
    let id: String
    let title: String
    /// Ranges of the title to draw in bold: the letters the search matched.
    let bold: [Range<String.Index>]
    let shortcut: String?
    /// Why it cannot run now; the row is greyed out.
    let unavailableReason: String?
}

/// What the palette lists for a query (docs/spec/command-palette.md):
/// empty, the recent commands then all by title; otherwise the fuzzy
/// matches of the titles, then the commands found only by a keyword.
@MainActor
enum PaletteModel {
    static func items(for query: String, registry: CommandRegistry, shortcut: (String) -> String?) -> [PaletteItem] {
        let commands = registry.commands
        func item(_ command: Command, bold: [Range<String.Index>] = []) -> PaletteItem {
            PaletteItem(id: command.id, title: command.title, bold: bold, shortcut: shortcut(command.id),
                        unavailableReason: command.unavailableReason())
        }

        if query.isEmpty {
            let recent = registry.recent.compactMap { registry.command($0) }
            let rest = commands.filter { !registry.recent.contains($0.id) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return (recent + rest).map { item($0) }
        }

        let byTitle = FuzzyRank.rank(query, commands.map(\.title))
        var seen = Set(byTitle.map(\.index))
        var items = byTitle.map { match in
            let title = commands[match.index].title
            return item(commands[match.index], bold: boldRanges(in: title, byteOffsets: match.positions))
        }
        let keywordTexts = commands.map { $0.keywords.joined(separator: " ") }
        for match in FuzzyRank.rank(query, keywordTexts) where !seen.contains(match.index) {
            seen.insert(match.index)
            items.append(item(commands[match.index]))
        }
        return items
    }

    /// The characters at the matched UTF-8 offsets, as ranges of the title.
    static func boldRanges(in title: String, byteOffsets: [Int]) -> [Range<String.Index>] {
        let utf8 = title.utf8
        return byteOffsets.compactMap { offset in
            guard offset < utf8.count else { return nil }
            let start = utf8.index(utf8.startIndex, offsetBy: offset)
            guard let char = String.Index(start, within: title) else { return nil }
            return char..<title.index(after: char)
        }
    }
}

/// The core's fuzzy ranking (cadex_fuzzy_rank, core/features/search).
enum FuzzyRank {
    struct Match {
        let index: Int
        /// Byte offsets in the text of the matched characters.
        let positions: [Int]
    }

    static func rank(_ query: String, _ texts: [String]) -> [Match] {
        let buffers = texts.map { Array($0.utf8) }
        let queryBytes = Array(query.utf8)
        var result = cadex_fuzzy_result()
        let status: Int32 = withTexts(buffers) { list in
            queryBytes.withUnsafeBufferPointer { q in
                cadex_fuzzy_rank(q.baseAddress, q.count, list.baseAddress, list.count, &result)
            }
        }
        defer { cadex_fuzzy_result_free(&result) }
        guard status == CADEX_OK, let matches = result.matches else { return [] }
        return (0..<result.count).map { i in
            let m = matches[i]
            let positions = (0..<Int(m.positions_count)).map { Int(result.positions![Int(m.positions_offset) + $0]) }
            return Match(index: Int(m.index), positions: positions)
        }
    }

    /// Hands the core a cadex_text per buffer, valid during `body`.
    private static func withTexts<R>(_ buffers: [[UInt8]], _ body: (UnsafeBufferPointer<cadex_text>) -> R) -> R {
        var pointers: [UnsafeMutablePointer<UInt8>] = []
        defer { pointers.forEach { $0.deallocate() } }
        let list = buffers.map { bytes -> cadex_text in
            let copy = UnsafeMutablePointer<UInt8>.allocate(capacity: max(bytes.count, 1))
            copy.initialize(from: bytes, count: bytes.count)
            pointers.append(copy)
            return cadex_text(text: copy, len: bytes.count)
        }
        return list.withUnsafeBufferPointer(body)
    }
}
