import Foundation

/// "Run on" another machine (docs/spec/worktrees.md; ADR 0031, the
/// minimum): the worktree is made there over ssh, and only once it exists
/// does the task enter the list, with its machine's name. The git there is
/// the remote's own; this Mac's core cannot reach it.
extension WorktreesController {
    public func remoteTasks(repo: String) -> [RemoteTask] { store.remoteTasks(repo) }

    /// Makes the task on `target`, from the branch checked out here (its
    /// origin's copy there when it has one). `folder`: where the repository
    /// is there, remembered for the next task; `clone`: clone origin into it
    /// when it holds none.
    public func makeRemote(name: String, repo: String, target: RunTarget, folder: String, clone: Bool) async -> RemotePrepared {
        let base = WorktreesCore.currentBranch(repo)
        let result = await remoteRunner.prepare(target, folder: folder, origin: Self.origin(of: repo), clone: clone,
                                                branch: WorktreesCore.branchName(name), base: base)
        guard case .made(let path, let branch) = result else { return result }
        store.setRemoteFolder(folder, repo: repo, on: target.destination)
        let task = RemoteTask(target: target, folder: folder, path: path, branch: branch)
        store.addRemote(task, repo: repo)
        store.setTask(task.noteKey) { info in
            info.status = .doing
            info.base = base
            info.created = Date()
        }
        publish()
        return result
    }

    /// Takes the worktree away there (git refuses one with changes); the
    /// task leaves the list only when it went. nil: removed.
    public func removeRemote(_ task: RemoteTask, repo: String) async -> RemotePrepared? {
        if let refused = await remoteRunner.remove(task) { return refused }
        store.forgetRemote(task, repo: repo)
        publish()
        return nil
    }

    /// The repository's `origin` URL, what a machine without it clones.
    public static func origin(of repo: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repo, "remote", "get-url", "origin"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let url = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !url.isEmpty ? url : nil
    }
}
