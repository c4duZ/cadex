import Checks
import Foundation
@testable import Memory
@testable import SessionKit

// Tests of the memory feature in the app. Run with `make macos-test` (see
// shared/checks/Checks.swift for why this is an executable).

nonisolated(unsafe) let fm = FileManager.default

func scratch() -> String {
    let dir = NSTemporaryDirectory() + "cadex-memory-\(UUID().uuidString)"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    return dir
}

func settings(of command: String) -> [String: Any] {
    let parts = command.components(separatedBy: " --settings ")
    guard parts.count > 1 else { return [:] }
    let path = String(parts[1].prefix { $0 != " " })
    return (fm.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

/// A stand-in engine: a script that records its arguments and exits `code`.
func fakeEngine(_ dir: String, code: Int) -> String {
    let path = dir + "/cadex-memory-\(code)"
    let script = "#!/bin/sh\necho \"$@\" > '\(dir)/args-\(code)'\nexit \(code)\n"
    fm.createFile(atPath: path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o755])
    return path
}

/// `git -C dir args…`; true when it worked.
@discardableResult
func git(_ dir: String, _ args: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", dir, "-c", "user.name=t", "-c", "user.email=t@t"] + args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

/// A repository with a commit and a task's worktree beside it.
func repoWithWorktree(_ dir: String) -> (repo: String, tree: String) {
    let repo = dir + "/acme", tree = dir + "/acme-task"
    try? fm.createDirectory(atPath: repo + "/src/deep", withIntermediateDirectories: true)
    git(repo, ["init", "-q"])
    git(repo, ["commit", "-q", "--allow-empty", "-m", "x"])
    git(repo, ["worktree", "add", "-q", tree])
    return (repo, tree)
}

/// The warm-up's result; nil when it did not start.
@MainActor
func warm(_ engine: String, _ folder: String, _ version: String) async -> Bool? {
    await withCheckedContinuation { (resume: CheckedContinuation<Bool?, Never>) in
        MainActor.assumeIsolated {
            let started = MemoryWarmUp.start(engine: engine, folder: folder, version: version) { resume.resume(returning: $0) }
            if !started { resume.resume(returning: nil) }
        }
    }
}

let featureTests: [(name: String, body: Checks.Body)] = [
    ("ten events, each `cadex memory-hook <Event>` with no matcher and 5 s", {
        let part = MemoryKit.part(tools: "/App/Cadex.app/Contents/Helpers/cadex", engine: nil, shareAcrossAccounts: true, environment: [:])
        let hooks = part.settings["hooks"] as? [String: Any] ?? [:]
        expect(hooks.keys.sorted() == ["PostCompact", "PostToolUse", "PreCompact", "SessionEnd", "SessionStart", "Stop",
                                       "StopFailure", "SubagentStart", "SubagentStop", "UserPromptSubmit"], "\(hooks.keys.sorted())")
        for event in MemoryKit.hookEvents {
            let entry = (hooks[event] as? [[String: Any]])?.first
            let hook = (entry?["hooks"] as? [[String: Any]])?.first
            expect(entry?["matcher"] == nil, "\(event) has a matcher")
            expect(hook?["command"] as? String == "/App/Cadex.app/Contents/Helpers/cadex memory-hook " + event, "\(String(describing: hook))")
            expect(hook?["timeout"] as? Int == 5 && hook?["type"] as? String == "command")
        }
        let spaced = MemoryKit.part(tools: "/a b/cadex", engine: nil, shareAcrossAccounts: true, environment: [:])
        let stop = (((spaced.settings["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first
        expect(stop?["command"] as? String == "'/a b/cadex' memory-hook Stop", "quoted when the shell needs it")
    }),
    ("the env: the engine and the data folder; the socket and tokens only for a test instance", {
        let home = fm.homeDirectoryForCurrentUser.path
        let plain = MemoryKit.part(tools: "/c", engine: "/App/Cadex.app/Contents/Helpers/cadex-memory", shareAcrossAccounts: true, environment: [:])
        expect(plain.settings["env"] as? [String: String] == [
            "CADEX_MEMORY_BIN": "/App/Cadex.app/Contents/Helpers/cadex-memory",
            "CADEX_MEMORY_DIR": home + "/Library/Application Support/Cadex/memory",
        ], "\(String(describing: plain.settings["env"]))")
        expect(plain.perAccount == nil, "shared across accounts: no workspace")
        expect(plain.pluginDirs.isEmpty, "no plugin found, none passed")
        let skilled = MemoryKit.part(tools: "/c", engine: nil, shareAcrossAccounts: true, plugin: "/App/Cadex.app/Contents/Resources/memory-plugin", environment: [:])
        expect(skilled.pluginDirs == ["/App/Cadex.app/Contents/Resources/memory-plugin"], "the skills plugin by --plugin-dir")
        let test = MemoryKit.part(tools: "/c", engine: nil, shareAcrossAccounts: true,
                                  environment: ["CADEX_SOCKETS_DIR": "/t/s", "CADEX_SESSIONS_DIR": "/t/k", "CADEX_MEMORY_DIR": "/t/m"])
        expect(test.settings["env"] as? [String: String] == [
            "CADEX_MEMORY_DIR": "/t/m", "CADEX_MEMORY_SOCKET": "/t/s/memory.sock", "CADEX_SESSIONS_DIR": "/t/k",
        ], "\(String(describing: test.settings["env"]))")
    }),
    ("consolidation in the session: the milestone percent in the env, and a task-ready request file per session", {
        let on = MemoryKit.part(tools: "/c", engine: nil, shareAcrossAccounts: true, consolidateAt: 70, environment: ["CADEX_MEMORY_DIR": "/t/m"])
        expect((on.settings["env"] as? [String: String])?["CADEX_MEMORY_CONSOLIDATE_AT"] == "70")
        let off = MemoryKit.part(tools: "/c", engine: nil, shareAcrossAccounts: true, environment: ["CADEX_MEMORY_DIR": "/t/m"])
        expect((off.settings["env"] as? [String: String])?["CADEX_MEMORY_CONSOLIDATE_AT"] == nil, "off: the hook never asks")
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        expect(MemoryKit.requestConsolidation(sessionID: "abc-1", environment: ["CADEX_MEMORY_DIR": dir]))
        expect(fm.fileExists(atPath: dir + "/consolidate/requests/abc-1.ready"))
        expect(!MemoryKit.requestConsolidation(sessionID: "../x", environment: ["CADEX_MEMORY_DIR": dir]), "no path tricks")
        expect(MemoryKit.consolidateNowText.hasPrefix("Consolidate this session into the project memory"), "the hook's asked_prefix")
    }),
    ("the memory agent: the config the engine reads, the accounts as folders, the app's own token", {
        expect(MemoryAgent.accountFolder("", home: "/U") == nil && MemoryAgent.accountFolder("~/.claude", home: "/U") == nil)
        expect(MemoryAgent.accountFolder("~/.claude-work", home: "/U") == "/U/.claude-work")
        expect(MemoryAgent.accountFolder("/Abs/acct", home: "/U") == "/Abs/acct")
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let config = MemoryAgent.Config(enabled: false, dailyBudgetUsd: 1, requireApproval: true, configDir: nil,
                                        projectAccounts: ["/r": "/U/.claude-work"], claude: "/b/claude")
        expect(MemoryAgent.write(config, folder: dir))
        let read = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: dir + "/agent.json")))) as? [String: Any] ?? [:]
        expect(read["enabled"] as? Bool == false && read["config_dir"] is NSNull && read["claude"] as? String == "/b/claude", "\(read)")
        expect((read["project_accounts"] as? [String: String])?["/r"] == "/U/.claude-work")
        expect(((try? fm.attributesOfItem(atPath: dir + "/agent.json"))?[.posixPermissions] as? Int) == 0o600)
        let token = MemoryAgent.appToken(tokens: dir + "/tokens")
        expect(token?.count == 64 && MemoryAgent.appToken(tokens: dir + "/tokens") == token, "made once, then reused")
        let env = MemoryAgent.environment(engine: "/e", token: "t", base: ["CADEX_MEMORY_DIR": "/m", "CLAUDECODE": "1", "PATH": "/bin"])
        expect(env["CADEX_SESSION_TOKEN"] == "t" && env["CADEX_MEMORY_BIN"] == "/e" && env["CLAUDECODE"] == nil && env["PATH"] == "/bin")
    }),
    ("the engine is found in the bundle, else in the debug build of make app", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let helper = dir + "/Cadex.app/Contents/Helpers/cadex-memory"
        try? fm.createDirectory(atPath: (helper as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: helper, contents: Data(), attributes: [.posixPermissions: 0o755])
        expect(MemoryKit.findEngine(bundle: dir + "/Cadex.app", source: "/nowhere/a/b/c/d/e.swift") == helper)
        let built = dir + "/repo/core/features/memory/server/target/debug/cadex-memory"
        try? fm.createDirectory(atPath: (built as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fm.createFile(atPath: built, contents: Data(), attributes: [.posixPermissions: 0o755])
        let source = dir + "/repo/apps/macos/features/memory/MemoryKit.swift"
        expect(MemoryKit.findEngine(bundle: dir + "/none.app", source: source) == built)
        expect(MemoryKit.findEngine(bundle: dir + "/none.app", source: "/nowhere/a/b/c/d/e.swift") == nil)
        // No source given: this repository's build, whoever calls (a default #filePath was the caller's).
        let repoBuild = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../../core/features/memory/server/target/debug/cadex-memory").standardized.path
        if fm.isExecutableFile(atPath: repoBuild) { expect(MemoryKit.findEngine(bundle: dir + "/none.app").map { URL(fileURLWithPath: $0).standardized.path } == repoBuild) }
    }),
    ("through the kit: hooks with agents.stateHooks off, a workspace per account only when not shared, gone when withdrawn", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/bin/cadex", environment: [:])
        kit.hooksEnabled = false
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: "/bin/cadex", engine: "/e", shareAcrossAccounts: false, environment: [:]))
        let file = settings(of: kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json"))
        expect((file["hooks"] as? [String: Any])?.count == 10, "\(file)")
        let env = file["env"] as? [String: String] ?? [:]
        expect(env["CADEX_MEMORY_WORKSPACE"] == SessionKit.accountKey(dir + "/acct"), "\(env)")
        expect(env["CADEX_MEMORY_BIN"] == "/e" && env["CADEX_SESSION_TOKEN"]?.count == 64, "\(env)")
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: "/bin/cadex", engine: "/e", shareAcrossAccounts: true, environment: [:]))
        let shared = settings(of: kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json"))
        expect((shared["env"] as? [String: String])?["CADEX_MEMORY_WORKSPACE"] == nil, "\(shared)")
        kit.withdraw(MemoryKit.partID)
        let off = settings(of: kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json"))
        expect(off["hooks"] == nil && (off["env"] as? [String: String])?["CADEX_MEMORY_DIR"] == nil, "\(off)")
    }),
    ("the project key: pinned to the engine's, one per repository, worktrees and subfolders included", {
        // The same value is pinned in core/features/memory/server/src/project_key.rs.
        expect(MemoryProject.key(root: "/Users/example/acme") == "9db38d359c2297b1")
        expect(MemoryProject.key(root: "/Users/example/acme/") == "9db38d359c2297b1")
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let (repo, tree) = repoWithWorktree(dir)
        let root = MemoryProject.canonical(repo)
        expect(root.hasPrefix("/private/"), "realpath, as the engine's canonicalize: \(root)")
        expect(MemoryProject.mainRoot(cwd: repo) == root && MemoryProject.mainRoot(cwd: repo + "/src/deep") == root)
        expect(MemoryProject.mainRoot(cwd: tree) == root, "a worktree is its main checkout's: \(MemoryProject.mainRoot(cwd: tree))")
        try? fm.createDirectory(atPath: dir + "/loose", withIntermediateDirectories: true)
        expect(MemoryProject.mainRoot(cwd: dir + "/loose") == MemoryProject.canonical(dir + "/loose"), "outside git: the folder itself")
    }),
    ("autoMemoryDirectory: the project's folder for a session in it or its worktree, the account's with sharing off, none without a folder", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let (repo, tree) = repoWithWorktree(dir)
        let memory = dir + "/memory"
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/bin/cadex", environment: [:])
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: "/bin/cadex", engine: nil, shareAcrossAccounts: true, environment: ["CADEX_MEMORY_DIR": memory]))
        let key = MemoryProject.key(root: MemoryProject.canonical(repo))
        let inRepo = settings(of: kit.claudeCommand(configDir: dir + "/acct", cwd: repo + "/src", defaultClaudeJSON: dir + "/none.json"))
        expect(inRepo["autoMemoryDirectory"] as? String == memory + "/auto/" + key, "\(inRepo)")
        let inTree = settings(of: kit.claudeCommand(configDir: nil, cwd: tree, defaultClaudeJSON: dir + "/none.json"))
        expect(inTree["autoMemoryDirectory"] as? String == memory + "/auto/" + key, "the worktree shares it: \(inTree)")
        let info = fm.contents(atPath: memory + "/auto/" + key + "/project.json").flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        expect(info?["root"] as? String == MemoryProject.canonical(repo) && info?["account"] is NSNull, "\(String(describing: info))")
        expect(settings(of: kit.claudeCommand(configDir: nil, defaultClaudeJSON: dir + "/none.json"))["autoMemoryDirectory"] == nil,
               "no folder known: Claude's own default")

        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: "/bin/cadex", engine: nil, shareAcrossAccounts: false, environment: ["CADEX_MEMORY_DIR": memory]))
        let account = SessionKit.accountKey(dir + "/acct")
        let own = settings(of: kit.claudeCommand(configDir: dir + "/acct", cwd: repo, defaultClaudeJSON: dir + "/none.json"))
        expect(own["autoMemoryDirectory"] as? String == memory + "/auto/" + account + "/" + key, "\(own)")
        let ownInfo = fm.contents(atPath: memory + "/auto/" + account + "/" + key + "/project.json").flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        expect(ownInfo?["account"] as? String == account, "\(String(describing: ownInfo))")
    }),
    ("the warm-up runs once per version, kept in the memory folder only when the engine exits 0", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let data = dir + "/data"
        try? fm.createDirectory(atPath: data, withIntermediateDirectories: true)
        let stamp = data + "/" + MemoryWarmUp.versionFile
        expect(MemoryWarmUp.isNeeded(version: "1.2", folder: data))
        expect(await warm(fakeEngine(dir, code: 1), data, "1.2") == false, "a failing engine")
        expect(!fm.fileExists(atPath: stamp), "a failure is tried again next launch")
        expect(await warm(fakeEngine(dir, code: 0), data, "1.2") == true)
        let args = (try? String(contentsOfFile: dir + "/args-0", encoding: .utf8)) ?? ""
        expect(args == "--warm --data-dir \(data)\n", args)
        expect(!MemoryWarmUp.isNeeded(version: "1.2", folder: data), "stamped in the folder")
        expect(await warm(fakeEngine(dir, code: 0), data, "1.2") == nil, "the same version: not again")
        expect(MemoryWarmUp.isNeeded(version: "1.3", folder: data), "a new version warms again")
        expect(MemoryWarmUp.isNeeded(version: "1.2", folder: dir + "/other"), "another folder (a test instance) has its own")
    }),
]
let exitCode = await Checks.run(featureTests + pageTests() + markerTests() + markerPlaceTests() + pageTextTests() + offTests() + panelTests() + panelDetailTests() + panelScreenTests() + panelSearchTests() + panelGraphTests())
exit(exitCode)
