import Foundation

/// A subagent's conversation as the tab shows it, the way Claude Code shows
/// it in the terminal (docs/spec/agents.md, Conversa do subagente): the task
/// and your messages, its replies, each tool call with what it ran on, and
/// under it a few lines of what came back (the owner, 2026-10-21: one quiet
/// line per tool looked ridiculous). Results are never kept whole: three
/// lines and how many more, so a 34 MB log still keeps tens of KB.
public enum AgentTranscriptEntry: Equatable, Sendable {
    /// The task the subagent got, or a later message to it.
    case prompt(String)
    case reply(String)
    /// "Edit", "App.swift", and for edits the lines taken out and put in.
    case tool(name: String, subject: String, diff: [AgentDiffLine])
    /// The first lines a tool gave back and how many more; failed in red.
    case result(lines: [String], more: Int, failed: Bool)
}

public struct AgentDiffLine: Equatable, Sendable {
    public let added: Bool
    public let text: String
}

/// One line of the log into entries, defensively: another program's format
/// (ADR 0019), so what it cannot read gives nothing.
enum AgentTranscriptParse {
    static let maxText = 4000
    static let previewLines = 3
    static let diffLines = 8

    static func entries(_ line: Data) -> [AgentTranscriptEntry] {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let message = object["message"] as? [String: Any] else { return [] }
        let type = object["type"] as? String
        if type == "user", let text = message["content"] as? String { return prompt(text) }
        let parts = message["content"] as? [[String: Any]] ?? []
        return parts.flatMap { part -> [AgentTranscriptEntry] in
            switch (type, part["type"] as? String) {
            case ("user", "text"): return prompt(part["text"] as? String ?? "")
            case ("user", "tool_result"): return [result(part)]
            case ("assistant", "text"):
                let text = trimmed(part["text"] as? String ?? "")
                return text.isEmpty ? [] : [.reply(text)]
            case ("assistant", "tool_use"):
                let input = part["input"] as? [String: Any] ?? [:]
                return [.tool(name: part["name"] as? String ?? "?", subject: subject(input), diff: diff(input))]
            default: return []
            }
        }
    }

    /// Claude Code's own marks ("[Request interrupted…") are not yours.
    private static func prompt(_ text: String) -> [AgentTranscriptEntry] {
        let text = trimmed(text)
        return text.isEmpty || text.hasPrefix("[Request interrupted") ? [] : [.prompt(text)]
    }

    static func trimmed(_ text: String) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > maxText ? String(text.prefix(maxText)) + "…" : text
    }

    /// A result's text, a string or a list of text parts, cut to a preview.
    static func result(_ part: [String: Any]) -> AgentTranscriptEntry {
        let text: String
        if let string = part["content"] as? String { text = string } else {
            text = (part["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return .result(lines: lines.prefix(previewLines).map { cut(String($0)) }, more: max(0, lines.count - previewLines),
                       failed: part["is_error"] as? Bool ?? false)
    }

    /// What a tool ran on, from its input: the file's name, the command,
    /// the pattern or the description; the first line, short.
    static func subject(_ input: [String: Any]) -> String {
        for key in ["file_path", "path", "command", "pattern", "url", "query", "description", "prompt"] {
            guard let value = input[key] as? String, !value.isEmpty else { continue }
            let text = key.hasSuffix("path") ? (value as NSString).lastPathComponent : value
            return cut(text.split(separator: "\n").first.map(String.init) ?? text, to: 80)
        }
        return ""
    }

    /// An edit's lines, taken out then put in, a few of each.
    static func diff(_ input: [String: Any]) -> [AgentDiffLine] {
        let edits = (input["edits"] as? [[String: Any]]) ?? [input]
        var lines: [AgentDiffLine] = []
        for edit in edits {
            guard let old = edit["old_string"] as? String, let new = edit["new_string"] as? String else { continue }
            lines += old.split(separator: "\n").prefix(diffLines).map { AgentDiffLine(added: false, text: cut(String($0))) }
            lines += new.split(separator: "\n").prefix(diffLines).map { AgentDiffLine(added: true, text: cut(String($0))) }
            if lines.count >= diffLines * 2 { break }
        }
        return lines
    }

    static func cut(_ line: String, to length: Int = 160) -> String {
        line.count > length ? String(line.prefix(length)) + "…" : line
    }

    // MARK: Long results, read without parsing them

    /// A long line the tab leaves out, told by its first 4 KB: a tool's
    /// result (a file read, a command's output) or an attachment (the
    /// skills list, the system prompt). They were 31 of the largest log's
    /// 34 MB (2026-10-21); never parsed, and never held whole.
    static let long = 64 * 1024

    static func isResult(head: Data) -> Bool { head.range(of: Data(#""type":"tool_result""#.utf8)) != nil }

    static func isLeftOut(head: Data) -> Bool { isResult(head: head) || head.range(of: Data(#""attachment":{"#.utf8)) != nil }

    /// A long result's preview from its first bytes: the JSON string after
    /// "content":" (or "text":" in a list), undone by hand up to where the
    /// bytes stop. `newlines` counts its lines over the whole line.
    static func longResult(head: Data, newlines: Int) -> AgentTranscriptEntry {
        let text = String(decoding: head, as: UTF8.self)
        guard let start = text.range(of: #""content":""#) ?? text.range(of: #""text":""#) else {
            return .result(lines: [], more: newlines + 1, failed: false)
        }
        let lines = unescaped(text[start.upperBound...]).split(separator: "\n", omittingEmptySubsequences: true)
        let shown = lines.dropLast().prefix(previewLines).map { cut(String($0)) }
        return .result(lines: Array(shown), more: max(0, newlines + 1 - shown.count), failed: false)
    }

    /// A JSON string's text up to its closing quote or the end of the bytes.
    static func unescaped(_ raw: Substring) -> String {
        var out = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            index = raw.index(after: index)
            if character == "\"" { break }
            guard character == "\\", index < raw.endIndex else { out.append(character); continue }
            let code = raw[index]
            index = raw.index(after: index)
            switch code {
            case "n": out.append("\n")
            case "t": out.append("  ")
            case "u":
                let end = raw.index(index, offsetBy: 4, limitedBy: raw.endIndex) ?? raw.endIndex
                if let value = UInt32(raw[index..<end], radix: 16), let scalar = UnicodeScalar(value) { out.unicodeScalars.append(scalar) }
                index = end
            default: out.append(code)
            }
        }
        return out
    }
}
