import Foundation
import Strings

/// A task whose worktree and agent live on another machine (ADR 0031, the
/// minimum): Cadex keeps where, never a copy of anything there.
public struct RemoteTask: Codable, Equatable, Sendable {
    public var target: RunTarget
    /// The repository's folder there, as the owner typed it (may start with ~/).
    public var folder: String
    /// The worktree there, as the preparation printed it.
    public var path: String
    public var branch: String
    public var created = Date()

    /// The key of its status and comment in the notes (one per machine and path).
    public var noteKey: String { "ssh://\(target.destination)\(path)" }
}

/// What the preparation over ssh ended in.
public enum RemotePrepared: Equatable, Sendable {
    case made(path: String, branch: String)
    /// No repository in the folder, and cloning was not asked.
    case noRepo
    /// ssh could not log in without a question (a password, a host key to
    /// confirm): the owner connects once in a tab, then tries again.
    case needsLogin(String)
    case failed(String)
}

/// Runs a script on another machine with the owner's `ssh`, never asking
/// anything (BatchMode): what needs an answer goes to a tab instead.
public struct RemoteTaskRunner: Sendable {
    /// The ssh binary (tests put a fake one that runs the script here).
    public var ssh = "/usr/bin/ssh"
    public var timeout: TimeInterval = 120

    public init() {}

    /// `ssh -o BatchMode=yes -o ConnectTimeout=10 -- <destination> "sh -c '<script>'"`.
    public func arguments(_ target: RunTarget, _ script: String) -> [String] {
        ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "--", target.destination, "sh -c " + RemoteTaskScript.quote(script)]
    }

    public func run(_ target: RunTarget, _ script: String) async -> (status: Int32, out: String, err: String) {
        let arguments = arguments(target, script)
        let ssh = self.ssh, timeout = self.timeout
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ssh)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            guard (try? process.run()) != nil else { return (-1, "", "ssh could not start") }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
            // Both pipes read at once: a full stderr pipe would block ssh.
            let errData = Box()
            let reader = Thread { errData.data = err.fileHandleForReading.readDataToEndOfFile() }
            reader.start()
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            while !reader.isFinished { usleep(1000) }
            return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData.data, as: UTF8.self))
        }.value
    }

    public func prepare(_ target: RunTarget, folder: String, origin: String?, clone: Bool, branch: String, base: String) async -> RemotePrepared {
        let result = await run(target, RemoteTaskScript.prepare(folder: folder, origin: origin, clone: clone, branch: branch, base: base))
        if result.status == 0, let made = RemoteTaskScript.made(result.out) { return .made(path: made.path, branch: made.branch) }
        if result.status == 3, result.out.contains("CADEX_NO_REPO") { return .noRepo }
        return Self.failure(result.status, result.err)
    }

    /// nil when removed; else the message (git's refusal, or ssh's).
    public func remove(_ task: RemoteTask) async -> RemotePrepared? {
        let result = await run(task.target, RemoteTaskScript.remove(folder: task.folder, path: task.path))
        return result.status == 0 && result.out.contains("CADEX_REMOVED") ? nil : Self.failure(result.status, result.err)
    }

    /// ssh's own failures exit 255: a login that needs a question, or the
    /// machine out of reach. The rest is the script's (git's words).
    static func failure(_ status: Int32, _ err: String) -> RemotePrepared {
        let message = err.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status == 255 else { return .failed(message.isEmpty ? "exit \(status)" : message) }
        let login = ["Permission denied", "Host key verification failed", "password", "passphrase"].contains { message.contains($0) }
        return login ? .needsLogin(message) : .failed(message.isEmpty ? T("The machine did not answer.", "A máquina não respondeu.") : message)
    }
}

/// A buffer one thread fills and another reads after it finished.
final class Box: @unchecked Sendable {
    var data = Data()
}
