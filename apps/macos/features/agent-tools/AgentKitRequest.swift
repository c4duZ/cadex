import Darwin
import Foundation

/// The kit asked for by the `claude` typed in a Cadex zsh tab (`cadex
/// claude`, plan 22 phase C). There is no session token in a tab, so the
/// request carries none: the app takes it only from a process under the
/// shell of one of its own terminals. That ancestry is read from the
/// kernel, starting at the connecting process (LOCAL_PEERPID), never from
/// the pids the request lists, which any process of this user could write.
public struct AgentKitRequest: Sendable, Equatable {
    /// The pids `cadex` listed (kept for the record; not trusted).
    public let pids: [Int32]
    /// The connecting process, its parent, and so on, from the kernel.
    public let ancestry: [Int32]
    /// The tab's CLAUDE_CONFIG_DIR; empty is the default account.
    public let configDir: String
    public let cwd: String
    /// The value of the owner's `--settings`, if given.
    public let userSettings: String?
    /// The owner's words, without `--settings`.
    public let arguments: [String]

    static func parse(_ object: [String: Any], ancestry: [Int32]) -> AgentKitRequest? {
        guard object["kit"] as? Bool == true else { return nil }
        let pids = (object["pids"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.int32Value }
        return AgentKitRequest(pids: pids, ancestry: ancestry, configDir: object["config_dir"] as? String ?? "",
                               cwd: object["cwd"] as? String ?? "", userSettings: object["user_settings"] as? String,
                               arguments: (object["args"] as? [Any] ?? []).compactMap { $0 as? String })
    }

    /// True when one of `shells` (the pids of Cadex's terminals' shells) is
    /// above the asking process.
    public func comesFrom(shells: [Int32]) -> Bool {
        ancestry.contains { pid in pid > 1 && shells.contains(pid) }
    }

    /// The process at the other end of a Unix socket.
    static func peer(_ fd: Int32) -> Int32? {
        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        // SOL_LOCAL (0) / LOCAL_PEERPID (2), <sys/un.h>.
        guard getsockopt(fd, 0, 2, &pid, &size) == 0, pid > 0 else { return nil }
        return pid
    }

    /// `pid` and its parents up to launchd, at most 32 (`cadex` sits a few
    /// levels under the shell at most).
    public static func ancestry(of pid: Int32) -> [Int32] {
        var out: [Int32] = []
        var current = pid
        while current > 1, out.count < 32 {
            out.append(current)
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { break }
            current = info.kp_eproc.e_ppid
        }
        return out
    }
}

/// What the app answers a kit request.
public enum AgentKitAnswer: Sendable, Equatable {
    /// The words before the owner's, the names to drop, the folder first on PATH.
    case kit(arguments: [String], unset: [String], pathFirst: String?)
    /// `cadex claude` then runs the real `claude` as typed.
    case refused(String)

    var json: [String: Any] {
        switch self {
        case .kit(let arguments, let unset, let pathFirst):
            var out: [String: Any] = ["ok": true, "args": arguments, "unset": unset]
            if let pathFirst { out["path_first"] = pathFirst }
            return out
        case .refused(let reason): return ["ok": false, "error": reason]
        }
    }
}

extension AgentToolsServer {
    /// A kit request, answered on the main thread; refused without a handler.
    func answerKit(_ object: [String: Any], _ client: Int32) {
        let ancestry = AgentKitRequest.peer(client).map(AgentKitRequest.ancestry(of:)) ?? []
        guard let request = AgentKitRequest.parse(object, ancestry: ancestry) else { Darwin.close(client); return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                let answer = self?.onKit?(request) ?? .refused("Cadex gives no kit here")
                Self.send(client, answer.json)
            }
        }
    }
}
