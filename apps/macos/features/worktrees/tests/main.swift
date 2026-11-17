import CCadex
import Checks
import Foundation
@testable import Worktrees

// Tests of the tasks' worktrees, on a real temporary repository. Run with
// `make macos-test` (see shared/checks/Checks.swift for why this is an executable).

nonisolated(unsafe) let fm = FileManager.default

@discardableResult
func git(_ dir: String, _ args: String...) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "-C", dir] + args
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

/// A repository with a commit, a .env git ignores and a .worktreeinclude naming it.
func fakeRepo() -> (home: String, repo: String) {
    let home = String(cString: realpath(NSTemporaryDirectory(), nil)) + "/cadex-wt-\(UUID().uuidString.prefix(8))"
    let repo = home + "/app"
    try? fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
    git(repo, "init", "--quiet", "--initial-branch=main")
    git(repo, "config", "user.name", "Teste")
    git(repo, "config", "user.email", "t@cadex")
    fm.createFile(atPath: repo + "/a.txt", contents: Data("um\n".utf8))
    fm.createFile(atPath: repo + "/.gitignore", contents: Data(".env\n".utf8))
    fm.createFile(atPath: repo + "/.worktreeinclude", contents: Data(".env\n".utf8))
    fm.createFile(atPath: repo + "/.env", contents: Data("TOKEN=x\n".utf8))
    git(repo, "add", "a.txt", ".gitignore", ".worktreeinclude")
    git(repo, "commit", "--quiet", "-m", "first")
    // The repository is in the workspace; its tasks' folder is not, yet.
    var out: UnsafeMutablePointer<UInt8>?
    var len = 0
    _ = cadex_workspace_authorize(repo, &out, &len)
    cadex_free(out)
    return (home, repo)
}

let localTests: [(name: String, body: Checks.Body)] = [
    ("the plan: a branch from the name, the folder beside the repository, what needs a yes first", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home) }
        let controller = WorktreesController()
        controller.store = WorktreesStore(path: home + "/notes.json")
        controller.setupHooks = [repo: ["pnpm install"]]
        let plan = controller.plan(name: "Corrigir login!", repo: repo)
        expect(plan.branch == "corrigir-login" && plan.base == "main", "\(plan)")
        expect(plan.root == repo + ".worktrees" && plan.path == repo + ".worktrees/corrigir-login")
        expect(plan.needsAuthorization && plan.hooksNeedConfirmation && plan.explainTrust)
        // Saying no to that folder and choosing another root (worktrees.root).
        controller.rootSetting = home + "/elsewhere"
        let moved = controller.plan(name: "Corrigir login!", repo: repo)
        let name = (repo as NSString).lastPathComponent
        expect(moved.root == home + "/elsewhere/" + name && moved.path == moved.root + "/corrigir-login", "\(moved)")
    }),
    ("a task made: its worktree and branch, the .env copied, the note in progress; the second plan needs no yes", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home); try? fm.removeItem(atPath: repo + ".worktrees") }
        let controller = WorktreesController()
        controller.store = WorktreesStore(path: home + "/notes.json")
        controller.setupHooks = [repo: ["pnpm install"]]
        let plan = controller.plan(name: "Corrigir login", repo: repo)
        guard case .success(let made) = controller.make(plan) else { return expect(false, "not made") }
        expect(made.copied == 1 && made.unmatched.isEmpty && fm.fileExists(atPath: plan.path + "/.env"), "\(made)")
        // The agent's status goes to its task only (plan 20): a task's folder, not the repository's.
        expect(taskOf(plan.path) == plan.path, "a task: \(String(describing: taskOf(plan.path)))")
        expect(taskOf(repo) == nil, "the repository itself is no task")
        let tasks = controller.tasks(repo: repo)
        expect(tasks.count == 1 && tasks[0].worktree.branch == "corrigir-login" && tasks[0].info?.status == .doing && tasks[0].info?.base == "main")
        expect(controller.note(for: plan.path) == "In Progress")
        controller.setComment("fixing the header", of: plan.path)
        expect(controller.note(for: plan.path) == "In Progress · fixing the header")
        let again = controller.plan(name: "Corrigir login", repo: repo)
        expect(again.branch == "corrigir-login-2" && !again.needsAuthorization && !again.hooksNeedConfirmation && !again.explainTrust, "\(again)")
        // The notes come back after a restart.
        let reread = WorktreesStore(path: home + "/notes.json")
        expect(reread.task(plan.path)?.comment == "fixing the header" && reread.repo(repo).trustExplained)
    }),
    ("a race's discard: tasks from one base, one deleted, git forgets it, its branch keeps the commit until deleted", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home); try? fm.removeItem(atPath: repo + ".worktrees") }
        let controller = WorktreesController()
        controller.store = WorktreesStore(path: home + "/notes.json")
        let one = controller.plan(name: "fix-1", repo: repo, base: "main")
        guard case .success = controller.make(one) else { return expect(false, "not made") }
        let two = controller.plan(name: "fix-2", repo: repo, base: "main")
        guard case .success = controller.make(two) else { return expect(false, "not made") }
        expect(one.base == "main" && two.branch == "fix-2")
        fm.createFile(atPath: two.path + "/a.txt", contents: Data("try 2\n".utf8))
        git(two.path, "commit", "--quiet", "-am", "try 2")
        fm.createFile(atPath: two.path + "/scratch.txt", contents: Data("never committed\n".utf8))
        expect(controller.discard(two.path, repo: repo) == nil)
        expect(!fm.fileExists(atPath: two.path), "deleted, with what was never committed")
        expect(sh("git -C '\(repo)' log -1 --format=%s fix-2") == "try 2\n", "the commit stays on the branch")
        expect(controller.tasks(repo: repo).map(\.worktree.branch) == ["fix-1"] && controller.store.task(two.path) == nil)
        expect(git(repo, "rev-parse", "--verify", "--quiet", "fix-2") == 0, "the branch stays")
        expect(controller.deleteBranch("fix-2", repo: repo) == nil && git(repo, "rev-parse", "--verify", "--quiet", "fix-2") != 0)
        expect(controller.deleteBranch("fix-1", repo: repo) != nil, "git refuses a branch checked out in a worktree")
    }),
    ("taking a task away: refused with a change and says what; with nothing to lose it goes", {
        let (home, repo) = fakeRepo()
        defer { try? fm.removeItem(atPath: home); try? fm.removeItem(atPath: repo + ".worktrees") }
        let controller = WorktreesController()
        controller.store = WorktreesStore(path: home + "/notes.json")
        let plan = controller.plan(name: "x", repo: repo)
        guard case .success = controller.make(plan), let task = controller.tasks(repo: repo).first?.worktree else { return expect(false, "not made") }
        fm.createFile(atPath: plan.path + "/a.txt", contents: Data("dois\n".utf8))
        expect(controller.whatWouldBeLost(task) == ["a.txt"])
        expect(controller.remove(task, repo: repo, deleteBranch: true) != nil && fm.fileExists(atPath: plan.path), "a change keeps it")
        git(plan.path, "checkout", "--quiet", "a.txt")
        expect(controller.whatWouldBeLost(task) == [])
        expect(controller.remove(task, repo: repo, deleteBranch: true) == nil && !fm.fileExists(atPath: plan.path))
        expect(controller.store.task(plan.path) == nil, "its note goes with it")
    }),
]
let exitCode = await Checks.run(localTests + remoteTests + environmentTests + newTaskTests)
exit(exitCode)
