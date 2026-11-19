import Foundation

/// A wiki page as the Memory page lists it: its title and where it came
/// from (docs/spec/memory.md, "Página Memory": sessão, conta e hora).
public struct MemoryPage: Equatable, Sendable {
    /// Absolute path of the file; `relative` is the path inside the wiki.
    public var path: String
    public var relative: String
    public var title: String
    public var kind: String?
    public var sessionID: String?
    /// Who wrote it, as the frontmatter says (`agent`, else the first source's author).
    public var agent: String?
    public var time: Date?
    public var summary: String?
    /// When an agent wrote it, as the frontmatter says; nil when only the file's date is known
    /// (a clone or a pull makes every file new: "LEARNED TODAY" must not count those).
    public var learnedAt: Date? = nil
    /// A session page of a session with no prompt and no tool (plan 35 H, `MemorySessions.isEmptyPage`):
    /// the lists leave it out.
    public var emptySession = false

    /// The engine's bookkeeping, not knowledge: _meta.md, the log of a month (log-2026-11.md) and the
    /// proposals waiting in _pending/ (they show as proposals, not pages).
    public var isEngineFile: Bool {
        relative.hasPrefix("_pending/") || relative == "_meta.md"
            || (!relative.contains("/") && relative.hasPrefix("log-") && relative.hasSuffix(".md"))
    }
}

/// A folder of the wiki with its pages and folders, or the wiki itself.
public struct MemoryFolder: Equatable, Sendable {
    public var name: String
    public var relative: String
    public var folders: [MemoryFolder] = []
    public var pages: [MemoryPage] = []

    public var count: Int { pages.count + folders.reduce(0) { $0 + $1.count } }
}

/// The wiki read from its folder: files only, no dotfiles (`.git`), the
/// folders first and by name, the pages newest first. Reads only the head
/// of each file (the frontmatter), off the main thread.
public enum MemoryWiki {
    /// Bytes read per page for the frontmatter.
    static let headBytes = 8 * 1024

    public nonisolated static func tree(_ wikiDir: String) -> MemoryFolder {
        folder(wikiDir, relative: "", name: (wikiDir as NSString).lastPathComponent)
    }

    nonisolated static func folder(_ path: String, relative: String, name: String) -> MemoryFolder {
        var result = MemoryFolder(name: name, relative: relative)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        for child in names.sorted() where !child.hasPrefix(".") {
            let full = path + "/" + child
            let rel = relative.isEmpty ? child : relative + "/" + child
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                result.folders.append(folder(full, relative: rel, name: child))
            } else if child.hasSuffix(".md") {
                result.pages.append(page(full, relative: rel))
            }
        }
        result.pages.sort { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
        return result
    }

    /// One page from its frontmatter; the file's date when it has no time.
    public nonisolated static func page(_ path: String, relative: String) -> MemoryPage {
        let head = readHead(path)
        let front = MemoryFrontmatter.parse(head)
        let name = ((relative as NSString).lastPathComponent as NSString).deletingPathExtension
        let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        let generated = front.map("generated")
        let written = MemoryJSON.date(front.scalar("updated_at")) ?? MemoryJSON.date(generated["at"])
        let sources = front.list("sources")
        var page = MemoryPage(path: path, relative: relative, title: front.scalar("title") ?? name,
                              kind: front.scalar("kind") ?? front.scalar("type"), sessionID: sessionID(front, relative: relative),
                              agent: front.scalar("agent") ?? sources.first?["author"] ?? generated["by"],
                              time: written ?? modified, summary: front.scalar("summary"), learnedAt: written)
        page.emptySession = relative.hasPrefix("sessions/") && MemorySessions.isEmptyPage(head: head)
        return page
    }

    /// The session a page came from: `session_id`, else the name of a
    /// `sessions/<id>.md` page, else a source naming a session.
    nonisolated static func sessionID(_ front: MemoryFrontmatter, relative: String) -> String? {
        if let id = front.scalar("session_id"), !id.isEmpty { return id }
        if relative.hasPrefix("sessions/"), !relative.dropFirst("sessions/".count).contains("/") {
            return ((relative as NSString).lastPathComponent as NSString).deletingPathExtension
        }
        for source in front.list("sources") {
            guard let resource = source["resource"] else { continue }
            // ai-memory://session/<id> is what the engine writes (seen in bkdg-center's pages,
            // 2026-11-18): without it a page never knew the session it came from.
            for prefix in ["ai-memory://session/", "session:", "sessions/", "claude-session:"] where resource.hasPrefix(prefix) {
                let id = String(resource.dropFirst(prefix.count))
                return id.hasSuffix(".md") ? String(id.dropLast(3)) : id
            }
        }
        return nil
    }

    /// The first 8 KB: enough for any frontmatter the engine writes.
    nonisolated static func readHead(_ path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: headBytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// "a1b2c3d4": the start of a session id, as the page shows it.
    public nonisolated static func shortID(_ id: String) -> String { String(id.prefix(8)) }
}

/// The YAML frontmatter, read only as far as the page needs: top-level
/// scalars, inline `[a, b]` lists, a list of one-level maps (`sources`)
/// and a one-level map (`generated`). Anything else is skipped, never an
/// error: a hand-edited page still lists with its file name.
public struct MemoryFrontmatter: Sendable {
    var scalars: [String: String] = [:]
    var maps: [String: [String: String]] = [:]
    var lists: [String: [[String: String]]] = [:]

    public func scalar(_ key: String) -> String? { scalars[key] }
    public func map(_ key: String) -> [String: String] { maps[key] ?? [:] }
    public func list(_ key: String) -> [[String: String]] { lists[key] ?? [] }

    public static func parse(_ text: String) -> MemoryFrontmatter {
        var front = MemoryFrontmatter()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.hasSuffix("\r") ? String($0.dropLast()) : String($0) }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return front }
        var key: String?
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") { continue }
            if !line.hasPrefix(" "), !line.hasPrefix("-"), let (k, v) = pair(line) {
                key = k
                if !v.isEmpty { front.scalars[k] = v }
                continue
            }
            guard let key else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                var item: [String: String] = [:]
                if let (k, v) = pair(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)) { item[k] = v }
                front.lists[key, default: []].append(item)
            } else if let (k, v) = pair(trimmed) {
                if front.lists[key] != nil, !front.lists[key]!.isEmpty {
                    front.lists[key]![front.lists[key]!.count - 1][k] = v
                } else {
                    front.maps[key, default: [:]][k] = v
                }
            }
        }
        return front
    }

    /// "key: value" with the value unquoted; nil when it is not a pair.
    static func pair(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        return (key, unquote(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
    }

    static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else { return value }
        let inner = String(value.dropFirst().dropLast())
        return first == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"") : inner.replacingOccurrences(of: "''", with: "'")
    }
}
