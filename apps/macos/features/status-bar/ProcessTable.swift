import Darwin
import Foundation

/// The processes of this user, their processor and memory, for the CPU, RAM and Cadex memory cards
/// (docs/spec/status-bar.md, Os cartões). Read only while one of those cards is open, every 2 s
/// with the stats. The system's own (WindowServer, root's) cannot be read without admin rights:
/// the cards say so and Activity Monitor shows them (measured 2026-11-18: 434 of 680 readable).
@MainActor
public final class ProcessTable {
    public struct Process: Equatable, Sendable {
        public var pid: pid_t
        public var parent: pid_t
        public var group: pid_t
        public var name: String
        /// Percent of one core over the last interval (can pass 100); nil on a first reading.
        public var cpu: Double?
        public var memory: UInt64
    }

    public static let shared = ProcessTable()
    private var lastTimes: [pid_t: UInt64] = [:]
    private var lastAt: UInt64 = 0
    private let timebase: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    /// Every readable process now; the processor share from the last call (forgotten when the
    /// cards close: `reset`).
    public func sample() -> [Process] {
        let now = mach_absolute_time()
        let elapsed = lastAt == 0 ? 0 : Double(now - lastAt) * timebase
        var times: [pid_t: UInt64] = [:]
        var out: [Process] = []
        for pid in Self.allPids() where pid > 0 {
            var usage = rusage_info_v4()
            let read = withUnsafeMutablePointer(to: &usage) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
            }
            guard read == 0 else { continue }
            let time = usage.ri_user_time + usage.ri_system_time
            times[pid] = time
            var cpu: Double?
            if elapsed > 0, let before = lastTimes[pid], time >= before {
                cpu = Double(time - before) * timebase / elapsed * 100
            }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            let bsd = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
            out.append(Process(pid: pid, parent: bsd ? pid_t(info.pbi_ppid) : 0, group: bsd ? pid_t(info.pbi_pgid) : 0,
                               name: Self.name(pid), cpu: cpu, memory: usage.ri_phys_footprint))
        }
        lastTimes = times
        lastAt = now
        return out
    }

    /// The cards closed: the next sample starts over.
    public func reset() {
        lastTimes = [:]
        lastAt = 0
    }

    private static func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let got = pids.withUnsafeMutableBufferPointer { proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size)) }
        return Array(pids.prefix(Int(max(got, 0))))
    }

    /// The process's name; Claude Code's executable is named for its version (".../claude/versions/2.1.327").
    static func name(_ pid: pid_t) -> String {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            return displayName(path: String(cString: path))
        }
        var name = [CChar](repeating: 0, count: 256)
        proc_name(pid, &name, 256)
        return String(cString: name)
    }

    /// Pure, for the tests: an app's name from its bundle, Claude Code's as "claude".
    public static func displayName(path: String) -> String {
        if path.contains("/claude/versions/") { return "claude" }
        let parts = path.split(separator: "/")
        if let app = parts.firstIndex(where: { $0.hasSuffix(".app") }), parts.last != nil, path.contains(".app/Contents/MacOS/") {
            let bundle = String(parts[app].dropLast(4))
            let exe = String(parts.last!)
            return exe == bundle ? bundle : exe
        }
        return parts.last.map(String.init) ?? path
    }

    /// "1.2 GB", "61 MB"
    public static func size(_ bytes: UInt64) -> String { SystemStats.sizeText(bytes) }
}
