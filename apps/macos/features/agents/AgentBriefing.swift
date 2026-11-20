import Foundation

/// The briefing Cadex writes when an agent goes on in another account in a new conversation
/// (docs/spec/agents.md, Trocar de conta): where the work stopped, read from the conversation's own
/// file, and that file's path for the rest. It goes in as the new session's first message.
///
/// Why not only the memory's handoff: the engine builds it from the session id the SessionEnd hook
/// reports, and a pane's Claude (a background session attached in it, a conversation that went on
/// in a new file) reported an older id, so the new account got an old summary, after the engine's
/// start-up, and nothing on screen said so (traced 2026-11-20). The file is the conversation
/// itself; the memory's briefing still comes by its hook.
public enum AgentBriefing {
    /// The end of the file read: the last requests are there, and a 300 MB log is not read whole.
    static let tailBytes = 4 << 20
    static let prompts = 8
    static let promptChars = 600
    static let replyChars = 2000

    /// What Claude Code writes as a user turn that is not the owner's words.
    static let notOwner = ["<command-", "<local-command", "<system-reminder", "<bash-", "<task-notification", "Caveat:"]

    /// The owner's last requests (oldest first) and Claude's last answer after them.
    public struct Stop: Equatable, Sendable {
        public var prompts: [String]
        public var reply: String?
    }

    /// Where the conversation in `transcript` stopped; nil when it does not read or has no request.
    public static func stop(transcript: String) -> Stop? {
        guard let handle = FileHandle(forReadingAtPath: transcript) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let cut = size > UInt64(tailBytes)
        try? handle.seek(toOffset: cut ? size - UInt64(tailBytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        var lines = data.split(separator: UInt8(ascii: "\n"))
        if cut, !lines.isEmpty { lines.removeFirst() }
        var stop = Stop(prompts: [], reply: nil)
        let skipped = ["\"isCompactSummary\":true", "\"isMeta\":true"].map { Data($0.utf8) }
        for line in lines where !skipped.contains(where: { line.range(of: $0) != nil }) {
            for entry in AgentTranscriptParse.entries(Data(line)) {
                switch entry {
                case .prompt(let text) where !notOwner.contains(where: text.hasPrefix):
                    stop.prompts.append(short(text, promptChars))
                    stop.reply = nil
                case .reply(let text): stop.reply = short(text, replyChars)
                default: break
                }
            }
        }
        stop.prompts = Array(stop.prompts.suffix(prompts))
        return stop.prompts.isEmpty ? nil : stop
    }

    /// The first message of the new conversation. In English, the agent's; it answers in the
    /// owner's language as always.
    public static func text(_ stop: Stop, transcript: String, fromAccount: String) -> String {
        var lines = ["This conversation continues work from another Claude Code account (\(fromAccount)), switched by the owner in Cadex.",
                     "The whole previous conversation is in \(transcript) (JSON lines); read it when you need more than what follows.",
                     "", "The owner's last requests, oldest first:"]
        lines += stop.prompts.enumerated().map { "\($0.offset + 1). " + $0.element.replacingOccurrences(of: "\n", with: " ") }
        if let reply = stop.reply { lines += ["", "Your last answer:", reply] }
        lines += ["", "Check the current state of the files before acting. Say in one or two lines where the work stands and wait for the owner's next message."]
        return lines.joined(separator: "\n")
    }

    static func short(_ text: String, _ limit: Int) -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? String(text.prefix(limit)) + "…" : text
    }
}
