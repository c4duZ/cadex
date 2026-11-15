import Checks
import Foundation
import SessionKit
@testable import Agents

// Hibernation (plan 19 phase F; docs/spec/agents.md, Hibernação): when an
// agent is due, its account from the conversation's file, and the resume
// typed in its terminal, by the kit, keeping the session's token.

let hibernationChecks: [(name: String, body: Checks.Body)] = [
    ("due only quiet for the minutes, not looked at, and never at 0", {
        let quiet = Date(timeIntervalSince1970: 1_000)
        let later = quiet.addingTimeInterval(30 * 60)
        expect(AgentHibernation.isDue(quietSince: quiet, lookedAt: false, minutes: 30, now: later))
        expect(!AgentHibernation.isDue(quietSince: quiet, lookedAt: false, minutes: 30, now: later.addingTimeInterval(-1)), "a second early")
        expect(!AgentHibernation.isDue(quietSince: quiet, lookedAt: true, minutes: 30, now: later), "looked at")
        expect(!AgentHibernation.isDue(quietSince: quiet, lookedAt: false, minutes: 0, now: later), "0 is off")
        expect(!AgentHibernation.isDue(quietSince: nil, lookedAt: false, minutes: 30, now: later), "working: no quiet time")
        expect(AgentHibernation.dueAt(quietSince: quiet, minutes: 30) == later && AgentHibernation.dueAt(quietSince: quiet, minutes: 0) == nil)
    }),
    ("the account comes from the conversation's file; the default one is no folder", {
        expect(AgentHibernation.configDir(transcript: "/Users/me/.claude-work/projects/-w/abc.jsonl", home: "/Users/me") == "/Users/me/.claude-work")
        expect(AgentHibernation.configDir(transcript: "/Users/me/.claude/projects/-w/abc.jsonl", home: "/Users/me") == nil)
        expect(AgentHibernation.configDir(transcript: "/nowhere.jsonl", home: "/Users/me") == nil)
    }),
    ("the resume goes into the folder and keeps the session kit's token", {
        let folder = NSTemporaryDirectory() + "cadex-hib-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let kit = SessionKit.forTests(folder: folder)
        // The first launch made a kit session with its token.
        _ = kit.claudeCommand(configDir: "/Users/me/.claude-work", defaultClaudeJSON: folder + "/none.json")
        let tokens = { (try? FileManager.default.contentsOfDirectory(atPath: folder + "/tokens")) ?? [] }
        guard let file = tokens().first(where: { $0.hasSuffix(".token") }), tokens().filter({ $0.hasSuffix(".token") }).count == 1 else { return expect(false, "\(tokens())") }
        let session = String(file.dropLast(6))
        let token = try String(contentsOfFile: folder + "/tokens/" + file, encoding: .utf8)
        let command = AgentHibernation.resumeCommand(sessionID: "abc", folder: "/w/my app", configDir: "/Users/me/.claude-work",
                                                     kitSession: session, skipPermissions: false, kit: kit)
        expect(command == "cd '/w/my app' && CLAUDE_CONFIG_DIR=/Users/me/.claude-work claude --resume abc", command)
        expect(tokens().filter { $0.hasSuffix(".token") } == [file], "the same kit session: \(tokens())")
        expect((try? String(contentsOfFile: folder + "/tokens/" + file, encoding: .utf8)) == token, "the token stays, so the app still knows the session")
        // The command it was opened with comes back: its flags, not its old conversation.
        let opened = kit.claudeCommand(configDir: nil, arguments: ["--model", "haiku", "--resume", "old", "--fork-session", "--dangerously-skip-permissions"],
                                       defaultClaudeJSON: folder + "/none.json")
        _ = opened
        let newest = tokens().filter { $0.hasSuffix(".token") && $0 != file }.first.map { String($0.dropLast(6)) }
        let same = AgentHibernation.resumeCommand(sessionID: "abc", folder: "/w", configDir: nil, kitSession: newest, skipPermissions: false, kit: kit)
        expect(same == "cd /w && claude --resume abc --model haiku --dangerously-skip-permissions", same)
        // A kit session whose token is gone gets a new one.
        let fresh = AgentHibernation.resumeCommand(sessionID: "abc", folder: "/w", configDir: nil, kitSession: "gone", skipPermissions: true, kit: kit)
        expect(fresh == "cd /w && claude --resume abc --dangerously-skip-permissions", fresh)
        expect(tokens().filter { $0.hasSuffix(".token") }.count == 3, "a new token for the gone one")
    }),
]
