import Foundation
import SessionKit

/// A pane whose Claude opened a background session with /resume ("Opening "X", running in the
/// background (69f16f5b)"): what the pane showed was that session, attached, not the conversation
/// that ran /resume. Reopening it with `--resume` of the outer conversation only printed the old
/// "Opening…" line again and attached nothing (the owner, 2026-11-20); the background session comes
/// back with `claude attach <job>`, Claude Code's own way.
public enum AgentAttachedJob {
    /// The end of the file read: the /resume that opened the job is among the last lines.
    static let tailBytes = 256 << 10
    static let mark = "running in the background ("

    /// The job the conversation in `transcript` last opened by /resume, when nothing the owner
    /// wrote came after it; nil otherwise.
    public static func job(transcript: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: transcript) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        var job: String?
        for line in data.split(separator: UInt8(ascii: "\n")) {
            let text = String(decoding: line, as: UTF8.self)
            if let found = jobID(in: text) { job = found; continue }
            for case .prompt(let words) in AgentTranscriptParse.entries(Data(line))
                where !AgentBriefing.notOwner.contains(where: words.hasPrefix) { job = nil }
        }
        return job
    }

    /// "…running in the background (69f16f5b)" → "69f16f5b" (letters, digits and dashes only).
    static func jobID(in text: String) -> String? {
        guard let start = text.range(of: mark, options: .backwards) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(of: ")") else { return nil }
        let id = String(rest[..<end])
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return !id.isEmpty && id.count <= 64 && id.unicodeScalars.allSatisfy(allowed.contains) ? id : nil
    }

    /// What the restore types: the screen cleared, into the folder, and the job attached in its
    /// account.
    public static func attachCommand(job: String, folder: String, configDir: String?) -> String {
        let account = configDir.map { "CLAUDE_CONFIG_DIR=" + SessionKit.quote($0) + " " } ?? ""
        return " clear && cd " + SessionKit.quote(folder) + " && " + account + "claude attach " + job
    }

    /// The conversation's file: `<account>/projects/<folder>/<id>.jsonl` (the default account is
    /// ~/.claude).
    public static func transcript(sessionID: String, folder: String, configDir: String?) -> String {
        let account = configDir ?? NSHomeDirectory() + "/.claude"
        return account + "/projects/" + AgentProjectFolder.name(for: folder) + "/" + sessionID + ".jsonl"
    }
}
