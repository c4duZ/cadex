//! The pseudo-terminal: start the shell on one, and talk to it through the
//! master side. POSIX only; the Windows app will need ConPTY here (ADR 0001).

const std = @import("std");
const c = std.c;
const shell_env = @import("shell_env.zig");

const Winsize = extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 };

// Not bound by Zig's std for macOS.
extern "c" fn forkpty(amaster: *c_int, name: ?[*]u8, termp: ?*const anyopaque, winp: ?*const Winsize) c.pid_t;
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
extern "c" fn tcgetpgrp(fd: c_int) c.pid_t;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern "c" fn usleep(microseconds: c_uint) c_int;
extern "c" fn proc_pidinfo(pid: c_int, flavor: c_int, arg: u64, buffer: ?*anyopaque, size: c_int) c_int;

/// <sys/proc_info.h>: PROC_PIDVNODEPATHINFO and struct proc_vnodepathinfo,
/// whose pvi_cdir.vip_path (the current directory) starts after a 152-byte
/// vnode_info. Measured with clang on macOS 27, 2026-10-19.
const PROC_PIDVNODEPATHINFO: c_int = 9;
const vnode_path_info_size = 2352;
const cwd_path_offset = 152;

/// _IOW('t', 103, struct winsize) on macOS.
const TIOCSWINSZ: c_ulong = 0x80087467;
const F_SETFD: c_int = 2;
const FD_CLOEXEC: c_int = 1;

pub const Size = struct {
    cols: u16,
    rows: u16,
    cell_width_px: u16 = 0,
    cell_height_px: u16 = 0,

    fn winsize(self: Size) Winsize {
        return .{
            .row = self.rows,
            .col = self.cols,
            .xpixel = self.cols *| self.cell_width_px,
            .ypixel = self.rows *| self.cell_height_px,
        };
    }
};

pub const Child = struct {
    /// Master side of the pty: read the shell's output, write its input.
    fd: c_int,
    pid: c.pid_t,
};

pub const SpawnError = error{ForkFailed};

/// Starts `shell_path` as a login shell on a new pty. Everything the child
/// needs is prepared by the caller before the fork: after fork() in a
/// threaded process only async-signal-safe calls are allowed, so the child
/// does nothing but chdir and execve.
pub fn spawn(
    shell_path: [*:0]const u8,
    argv: shell_env.Argv,
    envp: shell_env.Envp,
    cwd: ?[*:0]const u8,
    size: Size,
) SpawnError!Child {
    var fd: c_int = undefined;
    const ws = size.winsize();
    const pid = forkpty(&fd, null, null, &ws);
    if (pid < 0) return error.ForkFailed;
    if (pid == 0) {
        // A missing cwd is not fatal: the shell starts in the inherited dir.
        if (cwd) |dir| _ = c.chdir(dir);
        _ = c.execve(shell_path, argv, envp);
        c._exit(127);
    }
    // Keep the master out of processes the app starts later (git, formatters).
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC);
    return .{ .fd = fd, .pid = pid };
}

pub fn resize(fd: c_int, size: Size) error{ResizeFailed}!void {
    const ws = size.winsize();
    if (ioctl(fd, TIOCSWINSZ, &ws) != 0) return error.ResizeFailed;
}

pub fn writeAll(fd: c_int, bytes: []const u8) error{WriteFailed}!void {
    var rest = bytes;
    while (rest.len > 0) {
        const n = c.write(fd, rest.ptr, rest.len);
        if (n < 0) {
            switch (c.errno(n)) {
                .INTR, .AGAIN => continue,
                else => return error.WriteFailed,
            }
        }
        rest = rest[@intCast(n)..];
    }
}

/// True while a program other than the shell itself owns the terminal, such
/// as an agent, a server or `sleep`. Used to confirm before closing.
/// The current directory of the program in the foreground (the shell, or
/// what it runs), written into `buf`. Null if the system does not say.
/// Used when the shell does not report its directory with OSC 7.
pub fn currentDirectory(child: Child, buf: *[vnode_path_info_size]u8) ?[]const u8 {
    const group = tcgetpgrp(child.fd);
    const pid = if (group > 0) group else child.pid;
    const got = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, buf, vnode_path_info_size);
    if (got != vnode_path_info_size) return null;
    const path = std.mem.sliceTo(buf[cwd_path_offset..], 0);
    return if (path.len == 0) null else path;
}

pub const directory_buffer_size = vnode_path_info_size;

pub fn hasForegroundProcess(child: Child) bool {
    const group = tcgetpgrp(child.fd);
    return group > 0 and group != child.pid;
}

pub fn waitExitCode(pid: c.pid_t) i32 {
    var status: c_int = 0;
    while (c.waitpid(pid, &status, 0) < 0) {
        if (c.errno(@as(c_int, -1)) != .INTR) return -1;
    }
    return decodeStatus(status);
}

/// Exit code for a normal exit, 128 + signal for a killed shell (the same
/// convention shells use for $?).
fn decodeStatus(status: c_int) i32 {
    const signal = status & 0x7f;
    if (signal == 0) return (status >> 8) & 0xff;
    return 128 + signal;
}

/// SIGHUP, then SIGKILL if the child is still there after grace_ms.
pub fn hangUp(child: Child, grace_ms: u32) void {
    _ = c.kill(child.pid, .HUP);
    var waited: u32 = 0;
    while (waited < grace_ms) : (waited += 10) {
        if (c.waitpid(child.pid, null, c.W.NOHANG) != 0) return;
        _ = usleep(10 * 1000);
    }
    killNow(child);
}

pub fn killNow(child: Child) void {
    _ = c.kill(child.pid, .KILL);
    _ = c.waitpid(child.pid, null, 0);
}

test "exit status decoding follows the shell convention" {
    try std.testing.expectEqual(@as(i32, 0), decodeStatus(0));
    try std.testing.expectEqual(@as(i32, 3), decodeStatus(3 << 8));
    try std.testing.expectEqual(@as(i32, 128 + 9), decodeStatus(9));
}
