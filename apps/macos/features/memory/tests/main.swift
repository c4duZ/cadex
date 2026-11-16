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

/// The warm-up's result; nil when it did not start.
@MainActor
func warm(_ engine: String, _ folder: String, _ version: String, _ defaults: UserDefaults) async -> Bool? {
    nonisolated(unsafe) let defaults = defaults
    return await withCheckedContinuation { (resume: CheckedContinuation<Bool?, Never>) in
        MainActor.assumeIsolated {
            let started = MemoryWarmUp.start(engine: engine, folder: folder, version: version, defaults: defaults) { resume.resume(returning: $0) }
            if !started { resume.resume(returning: nil) }
        }
    }
}

let exitCode = await Checks.run([
    ("nine events, each `cadex memory-hook <Event>` with no matcher and 5 s", {
        let part = MemoryKit.part(tools: "/App/Cadex.app/Contents/Helpers/cadex", engine: nil, shareAcrossAccounts: true, environment: [:])
        let hooks = part.settings["hooks"] as? [String: Any] ?? [:]
        expect(hooks.keys.sorted() == ["PostCompact", "PostToolUse", "PreCompact", "SessionEnd", "SessionStart", "Stop",
                                       "SubagentStart", "SubagentStop", "UserPromptSubmit"], "\(hooks.keys.sorted())")
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
        let test = MemoryKit.part(tools: "/c", engine: nil, shareAcrossAccounts: true,
                                  environment: ["CADEX_SOCKETS_DIR": "/t/s", "CADEX_SESSIONS_DIR": "/t/k", "CADEX_MEMORY_DIR": "/t/m"])
        expect(test.settings["env"] as? [String: String] == [
            "CADEX_MEMORY_DIR": "/t/m", "CADEX_MEMORY_SOCKET": "/t/s/memory.sock", "CADEX_SESSIONS_DIR": "/t/k",
        ], "\(String(describing: test.settings["env"]))")
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
    }),
    ("through the kit: hooks with agents.stateHooks off, a workspace per account only when not shared, gone when withdrawn", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let kit = SessionKit(folder: dir + "/kit", toolsPath: "/bin/cadex", environment: [:])
        kit.hooksEnabled = false
        kit.contribute(MemoryKit.partID, MemoryKit.part(tools: "/bin/cadex", engine: "/e", shareAcrossAccounts: false, environment: [:]))
        let file = settings(of: kit.claudeCommand(configDir: dir + "/acct", defaultClaudeJSON: dir + "/none.json"))
        expect((file["hooks"] as? [String: Any])?.count == 9, "\(file)")
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
    ("the warm-up runs once per version and keeps it only when the engine exits 0", {
        let dir = scratch()
        defer { try? fm.removeItem(atPath: dir) }
        let suite = "cadex-memory-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        expect(MemoryWarmUp.isNeeded(version: "1.2", defaults: defaults))
        expect(await warm(fakeEngine(dir, code: 1), dir + "/data", "1.2", defaults) == false, "a failing engine")
        expect(defaults.string(forKey: MemoryWarmUp.versionKey) == nil, "a failure is tried again next launch")
        expect(await warm(fakeEngine(dir, code: 0), dir + "/data", "1.2", defaults) == true)
        let args = (try? String(contentsOfFile: dir + "/args-0", encoding: .utf8)) ?? ""
        expect(args == "--warm --data-dir \(dir)/data\n", args)
        expect(defaults.string(forKey: MemoryWarmUp.versionKey) == "1.2" && !MemoryWarmUp.isNeeded(version: "1.2", defaults: defaults))
        expect(await warm(fakeEngine(dir, code: 0), dir + "/data", "1.2", defaults) == nil, "the same version: not again")
        expect(MemoryWarmUp.isNeeded(version: "1.3", defaults: defaults), "a new version warms again")
    }),
])
exit(exitCode)
