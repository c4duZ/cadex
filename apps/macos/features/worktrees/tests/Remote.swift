import Checks
import Foundation
@testable import Worktrees

// "Run on" another machine (plan 23, phase C), with the "other machine"
// being this one: a fake ssh runs the remote command here with /bin/sh,
// on temporary repositories. No network, no real ssh.

/// A fake `ssh` in `dir`: drops the options and the destination and runs the
/// remote command, as sshd would with the remote's shell.
func fakeSSH(_ dir: String) -> String {
    let path = dir + "/ssh"
    fm.createFile(atPath: path, contents: Data("#!/bin/sh\nfor a; do last=\"$a\"; done\nexec /bin/sh -c \"$last\"\n".utf8),
                  attributes: [.posixPermissions: 0o755])
    return path
}

/// `/bin/sh -c text`'s standard output.
func sh(_ text: String, env: [String: String] = [:]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", text]
    process.environment = ProcessInfo.processInfo.environment.merging(env) { $1 }
    let out = Pipe()
    process.standardOutput = out
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try? process.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

@MainActor
func remoteController(_ home: String) -> WorktreesController {
    let controller = WorktreesController()
    controller.store = WorktreesStore(path: home + "/notes.json")
    controller.remoteRunner.ssh = fakeSSH(home)
    return controller
}

let pc = RunTarget(label: "pc", destination: "dev@pc.tail1234.ts.net")

let remoteTests: [(name: String, body: Checks.Body)] = [
    ("quoting survives quotes, spaces and $: what sh gets is the text", {
        for text in ["it's", "a b", "$HOME", "\"x\"", "back\\slash", ""] {
            expect(sh("printf %s " + RemoteTaskScript.quote(text)) == text, text)
        }
    }),
    ("Run on: the worktree made there from origin's base, the task listed with its machine, the next name made unique", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        let there = home + "/remote/app"
        git(home, "clone", "--quiet", repo, there)
        git(repo, "remote", "add", "origin", repo)
        let controller = remoteController(home)
        let first = await controller.makeRemote(name: "Fix login", repo: repo, target: pc, folder: there, clone: false)
        expect(first == .made(path: there + ".worktrees/fix-login", branch: "fix-login"), "\(first)")
        expect(fm.fileExists(atPath: there + ".worktrees/fix-login/a.txt"))
        expect(!fm.fileExists(atPath: there + ".worktrees/fix-login/.env"), "nothing of this Mac is copied there")
        let second = await controller.makeRemote(name: "Fix login", repo: repo, target: pc, folder: there, clone: false)
        expect(second == .made(path: there + ".worktrees/fix-login-2", branch: "fix-login-2"), "\(second)")
        let tasks = controller.remoteTasks(repo: repo)
        expect(tasks.map(\.branch) == ["fix-login", "fix-login-2"] && tasks[0].target == pc)
        expect(controller.store.task(tasks[0].noteKey)?.status == .doing && controller.store.task(tasks[0].noteKey)?.base == "main")
        expect(controller.store.remoteFolder(repo, on: pc.destination) == there, "the folder is remembered per machine")
        expect(controller.store.remoteTargets == [pc])
        // The notes read back, and a file from before plan 23 still reads whole.
        expect(WorktreesStore(path: home + "/notes.json").remoteTasks(repo).count == 2)
        fm.createFile(atPath: home + "/old.json", contents: Data(#"{"tasks":{"/a":{"status":"review","comment":"x","base":"main","created":0}},"repos":{}}"#.utf8))
        expect(WorktreesStore(path: home + "/old.json").task("/a")?.status == .review)
    }),
    ("no repository there: asked before cloning; cloned from origin when the owner says so", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        git(repo, "remote", "add", "origin", repo)
        let controller = remoteController(home)
        let there = home + "/remote/fresh"
        let refused = await controller.makeRemote(name: "Task", repo: repo, target: pc, folder: there, clone: false)
        expect(refused == .noRepo && controller.remoteTasks(repo: repo).isEmpty, "\(refused)")
        let cloned = await controller.makeRemote(name: "Task", repo: repo, target: pc, folder: there, clone: true)
        expect(cloned == .made(path: there + ".worktrees/task", branch: "task"), "\(cloned)")
        expect(fm.fileExists(atPath: there + "/a.txt"))
    }),
    ("removing a remote task: git's refusal with changes comes back; clean, it goes from there and from the list", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        let there = home + "/remote/app"
        git(home, "clone", "--quiet", repo, there)
        let controller = remoteController(home)
        _ = await controller.makeRemote(name: "Work", repo: repo, target: pc, folder: there, clone: false)
        let task = controller.remoteTasks(repo: repo)[0]
        fm.createFile(atPath: task.path + "/a.txt", contents: Data("changed\n".utf8))
        let refused = await controller.removeRemote(task, repo: repo)
        expect(refused != nil && fm.fileExists(atPath: task.path) && controller.remoteTasks(repo: repo).count == 1, "\(String(describing: refused))")
        git(task.path, "checkout", "--quiet", "--", "a.txt")
        let removed = await controller.removeRemote(task, repo: repo)
        expect(removed == nil && !fm.fileExists(atPath: task.path) && controller.remoteTasks(repo: repo).isEmpty, "\(String(describing: removed))")
        expect(controller.store.task(task.noteKey) == nil)
    }),
    ("ssh's own failures: a login that needs a question, or a machine out of reach", {
        expect(RemoteTaskRunner.failure(255, "dev@pc: Permission denied (publickey).") == .needsLogin("dev@pc: Permission denied (publickey)."))
        expect(RemoteTaskRunner.failure(255, "Host key verification failed.") == .needsLogin("Host key verification failed."))
        expect(RemoteTaskRunner.failure(255, "ssh: connect to host pc port 22: Operation timed out") == .failed("ssh: connect to host pc port 22: Operation timed out"))
        expect(RemoteTaskRunner.failure(128, "fatal: a branch named 'x' already exists") == .failed("fatal: a branch named 'x' already exists"))
        let args = RemoteTaskRunner().arguments(pc, "echo hi")
        expect(args.contains("BatchMode=yes") && args[args.count - 3] == "--" && args[args.count - 2] == pc.destination, "\(args)")
    }),
    ("the task's tab: in the worktree, the hooks, then claude, through a login shell; and the shell command", {
        let (home, _) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        let bin = home + "/bin"
        try? fm.createDirectory(atPath: bin, withIntermediateDirectories: true)
        fm.createFile(atPath: bin + "/claude", contents: Data("#!/bin/sh\npwd > \"$OUT\"\n".utf8), attributes: [.posixPermissions: 0o755])
        let folder = home + "/it's here"
        try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let command = RemoteTaskScript.agent(path: folder, hooks: ["echo hook >> \"$OUT.hooks\""])
        _ = sh(command, env: ["SHELL": "/bin/sh", "PATH": bin + ":/usr/bin:/bin", "OUT": home + "/out"])
        let pwd = (try? String(contentsOfFile: home + "/out", encoding: .utf8))?.trimmingCharacters(in: .newlines)
        expect(pwd.map { String(cString: realpath($0, nil)) } == String(cString: realpath(folder, nil)), "\(String(describing: pwd))")
        expect((try? String(contentsOfFile: home + "/out.hooks", encoding: .utf8)) == "hook\n", "the hook ran first")
        let line = RemoteTaskScript.sshLine(pc, RemoteTaskScript.shell(path: folder))
        expect(line.hasPrefix("ssh -t 'dev@pc.tail1234.ts.net' 'exec \"$SHELL\" -l -c '"), line)
    }),
]
