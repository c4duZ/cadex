import Foundation

/// A memory page read for showing it rendered (plan 34 D and E: never the raw .md): its body after
/// the frontmatter as headings, paragraphs and items, its tags, and its sources' sessions. Markdown
/// marks inside a line (`code`, **bold**) are dropped to plain text.
public enum MemoryPageText {
    public enum Block: Equatable, Sendable { case heading(String), paragraph(String), item(String) }

    /// The body's blocks: "## X" headings, "- x" or "* x" items, the rest joined into paragraphs.
    /// The title heading ("# X") is left out (the page's title shows it).
    public static func blocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in body(text).split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#") {
                flush()
                let level = line.prefix { $0 == "#" }.count
                if level > 1 { blocks.append(.heading(plain(String(line.dropFirst(level))))) }
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush()
                blocks.append(.item(plain(String(line.dropFirst(2)))))
            } else {
                paragraph.append(plain(line))
            }
        }
        flush()
        return blocks
    }

    /// What comes after the frontmatter (the whole text when there is none).
    public static func body(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return text }
        return lines[(end + 1)...].joined(separator: "\n")
    }

    /// The frontmatter's tags, inline ("tags: [a, b]") or as a list ("tags:" then "- a").
    public static func tags(_ text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [] }
        var tags: [String] = []
        var inTags = false
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if line.hasPrefix("tags:") {
                let rest = line.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("[") {
                    return rest.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) }.filter { !$0.isEmpty }
                }
                inTags = true
                continue
            }
            guard inTags else { continue }
            if trimmed.hasPrefix("- ") { tags.append(String(trimmed.dropFirst(2))) } else { break }
        }
        return tags
    }

    /// `code`, **bold**, *italic* and [text](link) as their plain text.
    static func plain(_ text: String) -> String {
        var out = text.trimmingCharacters(in: .whitespaces)
        out = out.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "`", "__"] { out = out.replacingOccurrences(of: mark, with: "") }
        return out
    }
}
