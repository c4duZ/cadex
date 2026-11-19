import Checks
import Foundation
@testable import Memory
@testable import SessionKit

// The memory turned off in a project or a conversation (plan 35 I).

func offTests() -> [(name: String, body: Checks.Body)] { [
    ("an off project's sessions get no memory part; a worktree of it neither; another project and a session without memory", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let (repo, tree) = repoWithWorktree(dir)
        let other = dir + "/other"
        try? fm.createDirectory(atPath: other, withIntermediateDirectories: true)
        let memory = dir + "/memory"
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/bin/cadex", environment: [:])
        kit.hooksEnabled = false
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: "/bin/cadex", engine: nil, shareAcrossAccounts: true,
                                                        plugin: "/plugin", environment: ["CADEX_MEMORY_DIR": memory]))
        let has = { (command: String) in
            let file = settings(of: command)
            return file["hooks"] != nil && (file["env"] as? [String: String])?["CADEX_MEMORY_DIR"] == memory && command.contains("--plugin-dir /plugin")
        }
        let launch = { (cwd: String) in kit.claudeCommand(configDir: nil, cwd: cwd, defaultClaudeJSON: dir + "/none.json") }
        expect(has(launch(repo)), "on by default")
        expect(MemoryOff.write(roots: [repo], memory: memory))
        let written = fm.contents(atPath: memory + "/" + MemoryOff.fileName).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        expect(written == "{\"roots\":[\"\(MemoryProject.canonical(repo))\"]}", written)
        expect(!has(launch(repo + "/src")) && settings(of: launch(repo + "/src"))["hooks"] == nil, "the off project: nothing")
        expect(!has(launch(tree)), "its task's worktree, outside the root")
        expect(has(launch(other)), "another project keeps it")
        expect(!has(kit.claudeCommand(configDir: nil, cwd: other, defaultClaudeJSON: dir + "/none.json", leaving: [MemoryKit.partID])),
               "New Session without Memory")
        expect(MemoryOff.write(roots: [], memory: memory))
        expect(has(launch(repo)), "back on")
    }),
    ("a paused session is a mark with a plain id, removed on resume and pruned after 30 days", {
        let memory = scratch()
        defer { try? fm.removeItem(atPath: memory) }
        expect(!MemoryOff.isPaused(sessionID: "s-1", memory: memory))
        expect(MemoryOff.setPaused(true, sessionID: "s-1", memory: memory) && MemoryOff.isPaused(sessionID: "s-1", memory: memory))
        expect(!MemoryOff.setPaused(true, sessionID: "../x", memory: memory), "never a path")
        let mode = (try? fm.attributesOfItem(atPath: memory + "/paused/s-1")[.posixPermissions] as? Int) ?? 0
        expect(mode == 0o600, "\(mode)")
        MemoryOff.prunePaused(memory: memory, now: Date().addingTimeInterval(31 * 86_400))
        expect(!MemoryOff.isPaused(sessionID: "s-1", memory: memory), "pruned")
        MemoryOff.setPaused(true, sessionID: "s-2", memory: memory)
        expect(MemoryOff.setPaused(false, sessionID: "s-2", memory: memory) && !MemoryOff.isPaused(sessionID: "s-2", memory: memory))
    }),
] }
