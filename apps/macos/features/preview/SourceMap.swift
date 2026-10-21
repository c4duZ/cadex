import Foundation

/// A source map (version 3), enough to say where a served line and column
/// came from (plan 16, phase C: React 19 keeps only the stack, in the code
/// the dev server serves). Index maps ("sections") are not read. Pure.
struct SourceMap {
    let sources: [String]
    let sourceRoot: String
    let mappings: String

    init?(json: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let sources = object["sources"] as? [String], let mappings = object["mappings"] as? String
        else { return nil }
        self.sources = sources
        sourceRoot = object["sourceRoot"] as? String ?? ""
        self.mappings = mappings
    }

    /// The original place of a 0-based served line and column: the last
    /// segment at or before the column, or the line's first one. The source
    /// as the map names it, with the root (SourceLookup resolves it).
    func original(line: Int, column: Int) -> (source: String, line: Int, column: Int)? {
        var source = 0, originalLine = 0, originalColumn = 0
        var row = 0
        for text in mappings.split(separator: ";", omittingEmptySubsequences: false) {
            var servedColumn = 0
            var found: (Int, Int, Int)?
            for segment in text.split(separator: ",") {
                guard let values = Self.vlq(segment), !values.isEmpty else { continue }
                servedColumn += values[0]
                guard values.count >= 4 else { continue }
                source += values[1]
                originalLine += values[2]
                originalColumn += values[3]
                if row == line, found == nil || servedColumn <= column { found = (source, originalLine, originalColumn) }
            }
            if row == line {
                guard let found, sources.indices.contains(found.0) else { return nil }
                return (name(sources[found.0]), found.1 + 1, found.2 + 1)
            }
            row += 1
        }
        return nil
    }

    func name(_ source: String) -> String {
        sourceRoot.isEmpty || source.hasPrefix("/") || source.contains("://")
            ? source : (sourceRoot.hasSuffix("/") ? sourceRoot : sourceRoot + "/") + source
    }

    /// "webpack://_N_E/./src/a.tsx" and "turbopack:///[project]/src/a.tsx"
    /// as "src/a.tsx"; "file:///x" as "/x"; "./src/a.tsx" as "src/a.tsx".
    static func normalized(_ name: String) -> String {
        var path = name
        if path.hasPrefix("file://") { path = String(path.dropFirst("file://".count)) }
        if path.hasPrefix("turbopack:///[project]/") { path = String(path.dropFirst("turbopack:///[project]/".count)) }
        if path.hasPrefix("webpack://") {
            path = String(path.dropFirst("webpack://".count))
            path = path.firstIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? path
        }
        while path.hasPrefix("./") { path.removeFirst(2) }
        return path
    }

    /// One segment's numbers: base64 digits of 5 bits, the 6th says more
    /// follow, the lowest bit of the value is the sign.
    static func vlq(_ segment: Substring) -> [Int]? {
        var values: [Int] = []
        var value = 0, shift = 0
        for char in segment.utf8 {
            guard let digit = Self.digits[char] else { return nil }
            value += (digit & 31) << shift
            if digit & 32 != 0 {
                shift += 5
                continue
            }
            values.append(value & 1 == 1 ? -(value >> 1) : value >> 1)
            value = 0
            shift = 0
        }
        return shift == 0 ? values : nil
    }

    private static let digits: [UInt8: Int] = Dictionary(uniqueKeysWithValues:
        Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".utf8).enumerated().map { ($1, $0) })
}
