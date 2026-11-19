import Foundation
import Strings

/// A folder of the Conhecimento tab's tree: its name ("decisions", or "(root)"), how many pages and
/// the pages, newest first (upstream's `to_folders`).
public struct PanelFolder: Equatable, Sendable {
    public var name: String
    public var pages: [PanelPageRow]
    public var count: Int { pages.count }
}

/// The Conhecimento tab (MemoryProject.dc.html; upstream's project.rs): the knowledge folders, the
/// machinery ones under "Sistema", and Atividade recente. Pure, so the tests read the seed.
public struct PanelKnowledge: Equatable, Sendable {
    public var folders: [PanelFolder]
    public var system: [PanelFolder]
    public var recent: [PanelPageRow]

    public static let rootFolder = "(root)"

    public init(pages: [PanelPageRow]) {
        var knowledge: [String: [PanelPageRow]] = [:]
        var machinery: [String: [PanelPageRow]] = [:]
        for page in pages {
            let folder = page.path.contains("/") ? String(page.path.split(separator: "/")[0]) : Self.rootFolder
            if Self.isSystem(page.path) { machinery[folder, default: []].append(page) } else { knowledge[folder, default: []].append(page) }
        }
        folders = Self.folders(knowledge)
        system = Self.folders(machinery)
        // Knowledge only, newest first, the path breaking a tie, 20 at most (upstream's Recent Activity).
        recent = Array(pages.filter { !Self.isSystem($0.path) }.sorted(by: Self.newestFirst).prefix(20))
    }

    /// Folders by name (upstream's BTreeMap), each newest first.
    static func folders(_ map: [String: [PanelPageRow]]) -> [PanelFolder] {
        map.keys.sorted().map { PanelFolder(name: $0, pages: map[$0]!.sorted(by: newestFirst)) }
    }

    static func newestFirst(_ a: PanelPageRow, _ b: PanelPageRow) -> Bool {
        let (x, y) = (a.updated ?? .distantPast, b.updated ?? .distantPast)
        return x != y ? x > y : a.path < b.path
    }

    /// Upstream's `is_system_page`: `_rules/` is knowledge; other `_` trees, `sessions/`, and the
    /// root's index.md, _meta.md and log-*.md are machinery.
    public static func isSystem(_ path: String) -> Bool {
        if path.hasPrefix("_rules/") { return false }
        if path.hasPrefix("_") || path.hasPrefix("sessions/") { return true }
        if path.contains("/") { return false }
        return path == "index.md" || path == "_meta.md" || (path.hasPrefix("log-") && path.hasSuffix(".md"))
    }
}

/// The project screen's words, upstream's in Portuguese (MemoryProject, MemoryAgent, MemorySession).
public extension PanelWords {
    /// Upstream's `fmt_tokens`: 950, 12,0k, 1,2M (the decimal comma in Portuguese).
    static func tokens(_ n: Int) -> String {
        let format = { (value: Double, unit: String) -> String in
            let text = String(format: "%.1f", value)
            return (Strings.language == .pt ? text.replacingOccurrences(of: ".", with: ",") : text) + unit
        }
        if n >= 1_000_000 { return format(Double(n) / 1_000_000, "M") }
        if n >= 1_000 { return format(Double(n) / 1_000, "k") }
        return String(n)
    }

    /// "14,0k / 4,0k" (input / output), or "—" when nothing was reported.
    static func inOut(_ usage: PanelUsage?) -> String {
        guard let usage else { return "—" }
        return tokens(usage.input) + " / " + tokens(usage.output)
    }

    /// Upstream's `duration_between`: 40s, 13m, 5h 33m, 5h, 2d; an open session has none.
    static func duration(_ start: Date?, _ end: Date?) -> String {
        guard let start, let end else { return end == nil && start != nil ? T("open", "aberta") : "—" }
        let secs = Int(abs(end.timeIntervalSince(start)))
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        let hours = mins / 60
        if hours < 24 { return mins % 60 == 0 ? "\(hours)h" : "\(hours)h \(mins % 60)m" }
        return "\(hours / 24)d"
    }

    /// Upstream's `short_id`: the id's last 8 characters.
    static func shortID(_ id: String) -> String { String(id.suffix(8)) }

    /// "sessão 1301a3b0…" in the trail (MemorySession.dc.html): the id's first 8.
    static func sessionCrumb(_ id: String) -> String { T("session ", "sessão ") + String(id.prefix(8)) + (id.count > 8 ? "…" : "") }

    /// "Última captura: há 9 horas · nenhuma sessão aberta" (the project's overview tab).
    static func projectCapture(_ last: Date?, open: Int, now: Date = Date()) -> String {
        let opens = switch open {
        case 0: T("no open session", "nenhuma sessão aberta")
        case 1: T("1 open session", "1 sessão aberta")
        default: T("\(open) open sessions", "\(open) sessões abertas")
        }
        return lastCapture(last, now: now) + " · " + opens
    }

    /// "18/11 21:13:34" in local time (the session's start and end; the ISO goes in the tooltip).
    static func clock(_ date: Date) -> String {
        let format = DateFormatter()
        format.dateFormat = Strings.language == .pt ? "dd/MM HH:mm:ss" : "MM/dd HH:mm:ss"
        return format.string(from: date)
    }

    static func iso(_ date: Date) -> String {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.string(from: date)
    }

    /// "1 versão, a mais recente primeiro".
    static func versions(_ n: Int) -> String {
        n == 1 ? T("1 version, newest first", "1 versão, a mais recente primeiro")
            : T("\(number(n)) versions, newest first", "\(number(n)) versões, a mais recente primeiro")
    }

    /// "386 caracteres".
    static func chars(_ n: Int) -> String { T("\(number(n)) characters", "\(number(n)) caracteres") }

    /// The token box's line: "0–0 de 0 respostas · 0 capturadas · 0 tokens nas correspondências".
    static func tokenLine(_ r: PanelTokenReport) -> String {
        let first = r.calls.isEmpty ? 0 : r.offset + 1
        let last = r.offset + r.calls.count
        return T("\(first)–\(last) of \(number(r.matchingCalls)) responses · \(number(r.callCount)) captured · \(number(r.matchingTokens)) tokens in matches",
                 "\(first)–\(last) de \(number(r.matchingCalls)) respostas · \(number(r.callCount)) capturadas · \(number(r.matchingTokens)) tokens nas correspondências")
    }
}
