import Foundation

/// A repository's .ai-memory.toml as the project's memory settings screen sees it (plan 32 D; the
/// owner, 2026-11-18: configure it "numa tela, ao invés de ficar mexendo nas coisas"). Only the
/// keys the engine forwards that the screen shows (docs/spec/memory.md, upstream's
/// docs/marker-file.md); writing changes those lines and keeps every other line, comment and key as
/// it was. Pure, so it is tested without a window.
public struct MemoryMarker: Equatable, Sendable {
    /// The project's and the workspace's names; empty: from the repository (Cadex's default).
    public var project = ""
    public var workspace = ""
    /// `[capture] ignore_paths`: files whose tool calls are not recorded.
    public var ignorePaths: [String] = []
    /// `drop_subagent_captures`: subagents' sessions are not stored.
    public var dropSubagents = false
    /// `[briefing]`: the brief at session start (on in Cadex), its size, and in subagents.
    public var briefing = true
    public var briefingChars = 4000
    public var subagentBriefing = false
    /// `[handoff]` and `[recovery] deliver_on_session_start`: on unless turned off.
    public var handoff = true
    public var recovery = true
    /// `[recall] default_global`: a search with no scope looks at every project.
    public var searchAll = false
    /// `[profile] contribute` and `consume`: on unless turned off.
    public var contribute = true
    public var consume = true

    public static let fileName = ".ai-memory.toml"
    /// The engine clamps the brief's size to this range (upstream: [1500, 20000]).
    public static let briefingRange = 1500...20000

    public init() {}

    /// The settings a file says; what it does not say keeps its default.
    public static func read(_ text: String) -> MemoryMarker {
        let doc = TomlLines(text)
        var marker = MemoryMarker()
        marker.project = doc.string(nil, "project") ?? ""
        marker.workspace = doc.string(nil, "workspace") ?? ""
        marker.ignorePaths = doc.array("capture", "ignore_paths") ?? []
        marker.dropSubagents = doc.flag(nil, "drop_subagent_captures") ?? false
        marker.briefing = doc.flag("briefing", "inject_on_session_start") ?? true
        marker.briefingChars = doc.value("briefing", "max_chars").flatMap(Int.init) ?? 4000
        marker.subagentBriefing = doc.flag("briefing", "inject_on_subagent_start") ?? false
        marker.handoff = doc.flag("handoff", "deliver_on_session_start") ?? true
        marker.recovery = doc.flag("recovery", "deliver_on_session_start") ?? true
        marker.searchAll = doc.flag("recall", "default_global") ?? false
        marker.contribute = doc.flag("profile", "contribute") ?? true
        marker.consume = doc.flag("profile", "consume") ?? true
        return marker
    }

    /// `text` with this marker's keys: a key already there takes the new value in its line; a key
    /// not there is written only when it differs from the default (an empty name removes the
    /// line, so the repository's name counts again). Everything else stays.
    public func written(over text: String) -> String {
        let defaults = MemoryMarker()
        var doc = TomlLines(text)
        func set(_ section: String?, _ key: String, _ value: String, isDefault: Bool) {
            if doc.has(section, key) || !isDefault { doc.set(section, key, value) }
        }
        func quoted(_ string: String) -> String { "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        for (key, name) in [("project", project), ("workspace", workspace)] {
            name.isEmpty ? doc.remove(nil, key) : doc.set(nil, key, quoted(name))
        }
        set("capture", "ignore_paths", "[" + ignorePaths.map(quoted).joined(separator: ", ") + "]", isDefault: ignorePaths.isEmpty)
        set(nil, "drop_subagent_captures", quoted(String(dropSubagents)), isDefault: dropSubagents == defaults.dropSubagents)
        set("briefing", "inject_on_session_start", String(briefing), isDefault: briefing == defaults.briefing)
        let chars = min(max(briefingChars, Self.briefingRange.lowerBound), Self.briefingRange.upperBound)
        set("briefing", "max_chars", String(chars), isDefault: chars == defaults.briefingChars)
        set("briefing", "inject_on_subagent_start", String(subagentBriefing), isDefault: subagentBriefing == defaults.subagentBriefing)
        set("handoff", "deliver_on_session_start", String(handoff), isDefault: handoff == defaults.handoff)
        set("recovery", "deliver_on_session_start", String(recovery), isDefault: recovery == defaults.recovery)
        set("recall", "default_global", String(searchAll), isDefault: searchAll == defaults.searchAll)
        set("profile", "contribute", String(contribute), isDefault: contribute == defaults.contribute)
        set("profile", "consume", String(consume), isDefault: consume == defaults.consume)
        return doc.text
    }
}

/// A TOML file as lines, for reading and changing single keys (`key = value`, top-level or in a
/// `[table]`) and keeping the rest byte for byte. Not a TOML parser: an array may span lines.
struct TomlLines {
    private(set) var lines: [String]

    init(_ text: String) { lines = text.isEmpty ? [] : text.components(separatedBy: "\n") }

    var text: String { lines.joined(separator: "\n") }

    /// The table a line opens (`[briefing]`), nil for other lines.
    private static func table(_ line: String) -> String? {
        let bare = line.split(separator: "#", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard bare.hasPrefix("["), bare.hasSuffix("]"), !bare.hasPrefix("[[") else { return nil }
        return String(bare.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// The key's line and how many lines its value takes (a multi-line array).
    private func find(_ section: String?, _ key: String) -> (Int, Int)? {
        var current: String?
        for (index, line) in lines.enumerated() {
            if let name = Self.table(line) { current = name; continue }
            guard current == section else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(key), trimmed.dropFirst(key.count).trimmingCharacters(in: .whitespaces).hasPrefix("=") else { continue }
            var span = 1
            if let value = rawValue(at: index), value.hasPrefix("["), !value.contains("]") {
                while index + span < lines.count, !lines[index + span - 1].contains("]") { span += 1 }
            }
            return (index, span)
        }
        return nil
    }

    private func rawValue(at index: Int) -> String? {
        guard let equals = lines[index].firstIndex(of: "=") else { return nil }
        return lines[index][lines[index].index(after: equals)...].trimmingCharacters(in: .whitespaces)
    }

    func has(_ section: String?, _ key: String) -> Bool { find(section, key) != nil }

    /// The value with its quotes and a trailing comment cut.
    func value(_ section: String?, _ key: String) -> String? {
        guard let (index, _) = find(section, key), let raw = rawValue(at: index) else { return nil }
        if raw.hasPrefix("\""), let end = raw.dropFirst().firstIndex(of: "\"") { return String(raw[raw.index(after: raw.startIndex)..<end]) }
        return raw.split(separator: "#", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func string(_ section: String?, _ key: String) -> String? { value(section, key).flatMap { $0.isEmpty ? nil : $0 } }

    /// true/false, "yes"/"no", "on"/"off", 1/0, quoted or bare (the engine's own reading).
    func flag(_ section: String?, _ key: String) -> Bool? {
        switch value(section, key)?.lowercased() {
        case "true"?, "yes"?, "on"?, "1"?: true
        case "false"?, "no"?, "off"?, "0"?: false
        default: nil
        }
    }

    /// The strings of an array, on one line or several.
    func array(_ section: String?, _ key: String) -> [String]? {
        guard let (index, span) = find(section, key) else { return nil }
        let joined = lines[index..<(index + span)].joined(separator: " ")
        guard let open = joined.firstIndex(of: "["), let close = joined.lastIndex(of: "]"), open < close else { return [] }
        return joined[joined.index(after: open)..<close].split(separator: ",").compactMap { item in
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return text.isEmpty ? nil : text
        }
    }

    /// The key's line takes `value` (a multi-line array becomes one line); a key not there goes at
    /// the end of its table, or of the top-level keys, or into a new table at the end.
    mutating func set(_ section: String?, _ key: String, _ value: String) {
        let line = "\(key) = \(value)"
        if let (index, span) = find(section, key) {
            lines.replaceSubrange(index..<(index + span), with: [line])
            return
        }
        guard let section else {
            let firstTable = lines.firstIndex { Self.table($0) != nil } ?? lines.count
            var at = firstTable
            while at > 0, lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
            lines.insert(line, at: at)
            return
        }
        if let start = lines.firstIndex(where: { Self.table($0) == section }) {
            var end = lines[(start + 1)...].firstIndex { Self.table($0) != nil } ?? lines.count
            while end > start + 1, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty { end -= 1 }
            lines.insert(line, at: end)
            return
        }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        if !lines.isEmpty { lines.append("") }
        lines += ["[\(section)]", line]
    }

    mutating func remove(_ section: String?, _ key: String) {
        if let (index, span) = find(section, key) { lines.removeSubrange(index..<(index + span)) }
    }
}
