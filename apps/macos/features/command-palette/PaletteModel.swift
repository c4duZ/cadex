import CCadex
import Foundation

/// What the palette lists for a query (docs/spec/command-palette.md):
/// empty, the recent commands then a section per area, each alphabetical
/// with the unavailable ones last; otherwise the fuzzy matches of the
/// titles, then the commands found only by a keyword, unavailable last.
@MainActor
enum PaletteModel {
    static func items(for query: String, registry: CommandRegistry, shortcut: (String) -> String?) -> [PaletteItem] {
        let commands = registry.commands
        func item(_ command: Command, bold: [Range<String.Index>] = [], section: CommandSections.Section? = nil) -> PaletteItem {
            PaletteItem(id: command.id, title: command.title, bold: bold, shortcut: shortcut(command.id),
                        unavailableReason: command.unavailableReason(), section: section?.title,
                        icon: CommandSections.section(of: command.id).icon)
        }
        func availableFirst(_ items: [PaletteItem]) -> [PaletteItem] {
            items.filter { $0.unavailableReason == nil } + items.filter { $0.unavailableReason != nil }
        }

        if query.isEmpty {
            let recent = registry.recent.compactMap { registry.command($0) }.map { item($0, section: CommandSections.recent) }
            let rest = commands.filter { !registry.recent.contains($0.id) }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            let grouped = Dictionary(grouping: rest) { CommandSections.section(of: $0.id).title }
            let sections = (CommandSections.all + [CommandSections.app]).flatMap { section in
                availableFirst((grouped[section.title] ?? []).map { item($0, section: section) })
            }
            return recent + sections
        }

        let byTitle = FuzzyRank.rank(query, commands.map(\.title))
        var seen = Set(byTitle.map(\.index))
        var items = byTitle.map { match in
            let title = commands[match.index].title
            return item(commands[match.index], bold: PaletteItem.boldRanges(in: title, byteOffsets: match.positions))
        }
        let keywordTexts = commands.map { $0.keywords.joined(separator: " ") }
        for match in FuzzyRank.rank(query, keywordTexts) where !seen.contains(match.index) {
            seen.insert(match.index)
            items.append(item(commands[match.index]))
        }
        return availableFirst(items)
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
