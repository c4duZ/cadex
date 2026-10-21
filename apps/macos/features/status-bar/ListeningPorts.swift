import Darwin
import Foundation

/// The TCP ports the programs in Cadex's terminals listen on (the Ports
/// item, docs/spec/status-bar.md): for each terminal's foreground process
/// group, its processes' sockets in the LISTEN state, read from the kernel
/// with libproc. No lsof, no other process; only the groups it is given.
public enum ListeningPorts {
    /// The ports, sorted, without repeats (IPv4 and IPv6 of one server).
    public static func ports(inGroups groups: [Int32]) -> [UInt16] {
        var found = Set<UInt16>()
        for group in groups where group > 0 {
            for pid in pids(inGroup: group) { found.formUnion(listening(pid)) }
        }
        return found.sorted()
    }

    static func pids(inGroup group: Int32) -> [Int32] {
        let size = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(group), nil, 0)
        guard size > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(size) / MemoryLayout<Int32>.size + 8)
        let got = proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(group), &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        return Array(pids.prefix(Int(got) / MemoryLayout<Int32>.size)).filter { $0 > 0 }
    }

    static func listening(_ pid: Int32) -> [UInt16] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: count)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, size)
        guard got > 0 else { return [] }
        var ports: [UInt16] = []
        for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.size) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var info = socket_fdinfo()
            let read = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard read == Int32(MemoryLayout<socket_fdinfo>.size), info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
            let tcp = info.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
            // The port is in network byte order.
            ports.append(UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)))
        }
        return ports
    }
}
