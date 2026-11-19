import Foundation

/// One conversation of the history (docs/spec/agents.md, Histórico): a
/// transcript file in an account's projects/, what it is about and where
/// it ran. Kept in the history's index (AgentHistoryStore) with how far the
/// file was read, so a growing transcript is read only where it grew.
public struct AgentHistoryEntry: Codable, Equatable, Sendable {
    /// The session id: the file's name.
    public var id: String
    public var path: String
    /// The account folder the file is in: the one that resumes it.
    public var account: String
    /// Where it ran, from its lines (a conversation of the repository
    /// resumed in a worktree keeps writing in the repository's project
    /// folder, test of 2026-11-14), not from the folder's name.
    public var cwd = ""
    public var branch = ""
    public var started: Date?
    public var updated: Date?
    public var firstPrompt = ""
    /// The title Claude gave it, and the one the user gave (`/rename`), which wins.
    public var aiTitle = ""
    public var customTitle = ""
    /// Continued from another conversation (another account's, by
    /// --fork-session): the copied lines carry the origin's session id
    /// (AgentHistoryReader.place has the two forms). Its subagents stay in
    /// the origin's folder.
    public var origin: String?
    public var originPath: String?
    /// Bytes read so far; only whole lines count.
    public var offset: UInt64 = 0
    /// Lines that did not read (another Claude Code version): skipped.
    public var unreadable = 0

    public init(id: String, path: String, account: String) {
        self.id = id
        self.path = path
        self.account = account
    }

    public var title: String {
        [customTitle, aiTitle, firstPrompt].first { !$0.isEmpty } ?? id
    }

    /// Whether the owner said anything in it: a prompt of theirs, or a title Claude gave from one
    /// (a first prompt starting with "<" is not read as one). Without it the conversation is empty
    /// (a panel opened and closed, only a /command): upstream's empty session, no prompt and no
    /// tool, as a tool runs only after a prompt (plan 35 H; the lists leave it out).
    public var hasPrompt: Bool { !firstPrompt.isEmpty || !aiTitle.isEmpty }
}

/// Reads the new part of a transcript into its entry and gives the texts to
/// search: what the user typed and what Claude answered, never a tool's
/// result. In 256 KB chunks; a line over 64 KB is a tool result or a pasted
/// blob and is skipped whole.
public enum AgentHistoryReader {
    static let chunk = 256 * 1024
    static let longLine = 64 * 1024
    static let textCap = 4 * 1024

    /// Off the main thread. Returns the texts found in the new lines.
    public static func readNew(_ entry: inout AgentHistoryEntry) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: entry.path) else { return [] }
        defer { try? handle.close() }
        try? handle.seek(toOffset: entry.offset)
        var texts: [String] = []
        var pending = Data()
        // Where a huge line began, while it is being dropped.
        var hugeFrom: UInt64?
        // Each chunk in its own autorelease pool: the JSON objects of 2.5 GB
        // of lines otherwise lived until the whole refresh ended (2 GB peak,
        // measured 2026-11-14).
        while let data = autoreleasepool(invoking: { try? handle.read(upToCount: chunk) }), !data.isEmpty {
            autoreleasepool {
            pending.append(data)
            // Line ends by memchr over the raw bytes: Data's own firstIndex
            // walked byte by byte and was most of the time (sample, 2026-11-14).
            let ends: [Int] = pending.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return [] }
                var found: [Int] = []
                var at = 0
                while at < raw.count, let hit = memchr(base + at, 0x0A, raw.count - at) {
                    let index = base.distance(to: UnsafeRawPointer(hit))
                    found.append(index)
                    at = index + 1
                }
                return found
            }
            var start = 0
            for end in ends {
                let line = pending.subdata(in: start..<end)
                if hugeFrom != nil { hugeFrom = nil } else if line.count <= longLine { texts += read(line, into: &entry) }
                entry.offset += UInt64(end - start + 1)
                start = end + 1
            }
            pending = start == 0 ? pending : pending.subdata(in: start..<pending.count)
            // A huge line is never held whole: drop it as it passes.
            if pending.count > longLine {
                if hugeFrom == nil { hugeFrom = entry.offset }
                entry.offset += UInt64(pending.count)
                pending.removeAll()
            }
            }
        }
        // The file ended inside a huge line still being written: read it
        // again from its start next time, so the offset stays on a line start.
        if let hugeFrom { entry.offset = hugeFrom }
        return texts
    }

    static let wanted: Set<String> = ["user", "assistant", "ai-title", "custom-title"]

    /// The conversation a transcript was continued from, from its first
    /// 256 KB only (the copied lines come first); nil when it was not.
    public static func origin(ofFile path: String, id: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        var entry = AgentHistoryEntry(id: id, path: path, account: "")
        let head = (try? handle.read(upToCount: chunk)) ?? Data()
        var start = head.startIndex
        while entry.origin == nil, let end = head[start...].firstIndex(of: 0x0A) {
            let line = head[start..<end]
            if line.count <= longLine { _ = read(line, into: &entry) }
            start = head.index(after: end)
        }
        return entry.origin
    }

    /// One line: its place, dates, titles and origin into the entry; its texts out.
    static func read(_ line: Data, into entry: inout AgentHistoryEntry) -> [String] {
        guard !line.isEmpty else { return [] }
        // Most bytes are lines nobody reads here (API requests, attachments,
        // tool results: 1.1 GB of the owner's 2.5 GB, 2026-11-14): the top
        // level says so without building the JSON.
        let top = topLevel(line)
        if top.known, top.type == nil {
            entry.unreadable += 1
            return []
        }
        if top.known, !wanted.contains(top.type ?? "") || top.toolResult { return [] }
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else {
            entry.unreadable += 1
            return []
        }
        switch object["type"] as? String {
        case "ai-title":
            if let title = object["aiTitle"] as? String { entry.aiTitle = cut(title, 200) }
            return []
        case "custom-title":
            if let title = object["customTitle"] as? String { entry.customTitle = cut(title, 200) }
            return []
        case "user", "assistant":
            place(object, into: &entry)
            return texts(object, into: &entry)
        default:
            return []
        }
    }

    private static func place(_ object: [String: Any], into entry: inout AgentHistoryEntry) {
        if let cwd = object["cwd"] as? String, !cwd.isEmpty { entry.cwd = cwd }
        if let branch = object["gitBranch"] as? String, !branch.isEmpty { entry.branch = branch }
        if let stamp = (object["timestamp"] as? String).flatMap(date) {
            if entry.started == nil { entry.started = stamp }
            entry.updated = max(entry.updated ?? stamp, stamp)
        }
        // Two forms of a copy: older versions kept the origin's sessionId
        // on the copied lines (~/.claude-diogo, October); 2.1.325 rewrites
        // sessionId and keeps the origin's id in session_id on the first
        // copied message (fork made on 2026-11-14).
        if entry.origin == nil {
            for key in ["sessionId", "session_id"] {
                if let session = object[key] as? String, session != entry.id, !session.isEmpty {
                    entry.origin = session
                    break
                }
            }
        }
    }

    private static func texts(_ object: [String: Any], into entry: inout AgentHistoryEntry) -> [String] {
        guard object["isMeta"] as? Bool != true, object["toolUseResult"] == nil,
              let message = object["message"] as? [String: Any] else { return [] }
        var found: [String] = []
        if let text = message["content"] as? String { found.append(text) }
        for part in message["content"] as? [[String: Any]] ?? [] where part["type"] as? String == "text" {
            if let text = part["text"] as? String { found.append(text) }
        }
        // Claude Code's own wrappers (commands, reminders) are not what was said.
        // and neither is the Esc's mark, which titled a conversation (2026-11-14).
        found = found.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("<") && !$0.hasPrefix("[Request interrupted") }
        // The summary Claude writes when it compacts a conversation is not
        // what the user asked ("This session is being continued…", seen in
        // the owner's history, 2026-11-14).
        let summary = object["isCompactSummary"] as? Bool == true
        if object["type"] as? String == "user", !summary, entry.firstPrompt.isEmpty, let first = found.first {
            entry.firstPrompt = cut(first.split(separator: "\n").first.map(String.init) ?? first, 200)
        }
        return found.map { cut($0, textCap) }
    }

    /// The top-level "type" value and whether a top-level "toolUseResult"
    /// is there, in one pass over the bytes (strings and nesting followed);
    /// `known` is false when the line does not look like an object.
    static func topLevel(_ line: Data) -> (known: Bool, type: String?, toolResult: Bool) {
        line.withUnsafeBytes { raw -> (Bool, String?, Bool) in
            let bytes = raw.bindMemory(to: UInt8.self)
            guard bytes.first == UInt8(ascii: "{") else { return (false, nil, false) }
            var depth = 0, i = 0, inString = false, keyStart = -1
            var type: String?, toolResult = false
            var expectKey = true
            func text(_ from: Int, _ to: Int) -> String { String(decoding: UnsafeBufferPointer(rebasing: bytes[from..<to]), as: UTF8.self) }
            var key = ""
            while i < bytes.count {
                let c = bytes[i]
                if inString {
                    if c == UInt8(ascii: "\\") { i += 2; continue }
                    if c == UInt8(ascii: "\"") {
                        inString = false
                        if depth == 1 {
                            let value = text(keyStart, i)
                            if expectKey { key = value } else if key == "type" { type = value }
                            if expectKey, value == "toolUseResult" { toolResult = true }
                        }
                    }
                } else {
                    switch c {
                    case UInt8(ascii: "\""):
                        inString = true
                        keyStart = i + 1
                    case UInt8(ascii: "{"), UInt8(ascii: "["): depth += 1; if depth == 1 { expectKey = true }
                    case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
                    case UInt8(ascii: ":"): if depth == 1 { expectKey = false }
                    case UInt8(ascii: ","): if depth == 1 { expectKey = true }
                    default: break
                    }
                }
                i += 1
            }
            return (true, type, toolResult)
        }
    }

    static func cut(_ text: String, _ limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit))
    }

    /// One formatter of each kind for every line: making one per line was
    /// the other half of the time (ICU, sample of 2026-11-14). The class is
    /// thread-safe.
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) static let whole = ISO8601DateFormatter()

    static func date(_ text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }
}
