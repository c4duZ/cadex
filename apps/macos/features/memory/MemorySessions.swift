import Foundation

/// What the memory says about one session beyond its page (plan 35 H): the briefing it started
/// with, as the engine kept it, and whether its page is of an empty session.
public enum MemorySessions {
    /// The briefing `session` received at its SessionStart, as Claude Code got it: the engine keeps
    /// the `/handoff` answer in `<memory>/agent/briefings/<session>.md` (plan 35 D, 30 days), and
    /// the hook drops upstream's backfill marker lines and trims it (hook_client.zig
    /// `briefingText`), so this does the same. Read from the disk, as projects.json is: it works
    /// with the engine down. Nil when none was kept or the id is not a plain one.
    public nonisolated static func received(session: String, folder: String) -> String? {
        guard let path = briefingPath(session: session, folder: folder),
              let data = FileManager.default.contents(atPath: path) else { return nil }
        let text = shown(String(decoding: data, as: UTF8.self))
        return text.isEmpty ? nil : text
    }

    /// `<memory>/agent/briefings/<session>.md`, for an id the engine would have used as a file
    /// name (audit.rs `session_file_name`: letters, digits, `-` and `_`, at most 128).
    nonisolated static func briefingPath(session: String, folder: String) -> String? {
        let fits = !session.isEmpty && session.count <= 128
            && session.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
        return fits ? folder + "/agent/briefings/" + session + ".md" : nil
    }

    /// The kept answer as the session read it.
    nonisolated static func shown(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("<!-- ai-memory:backfill ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A session page of a session with no prompt and no tool (upstream's
    /// `session_has_substantive_observation`; plan 35 C stopped writing them, older ones remain):
    /// upstream's own page (its "Session metadata") with neither its "Prompts" nor its "Tool
    /// calls" section, both written right after the metadata, inside the head the list reads. A
    /// page an agent rewrote has no metadata block and stays.
    nonisolated static func isEmptyPage(head: String) -> Bool {
        head.contains("\n## Session metadata\n") && !head.contains("\n## Prompts\n") && !head.contains("\n## Tool calls\n")
    }
}
