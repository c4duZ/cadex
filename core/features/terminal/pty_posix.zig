//! The pseudo-terminal on the Mac: forkpty, and the master side to talk to
//! the shell. The interface is `pty.zig`; `pty_windows.zig` is ConPTY.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const c = std.c;
const shell_env = @import("shell_env.zig");
const pty = @import("pty.zig");
const Size = pty.Size;

const Winsize = extern struct { row: u16, col: u16, xpixel: u16, ypixel: u16 };

// Not bound by Zig's std for macOS.
extern "c" fn forkpty(amaster: *c_int, name: ?[*]u8, termp: ?*const anyopaque, winp: ?*const Winsize) c.pid_t;
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
extern "c" fn tcgetpgrp(fd: c_int) c.pid_t;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
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

fn winsize(size: Size) Winsize {
    return .{
        .row = size.rows,
        .col = size.cols,
        .xpixel = size.cols *| size.cell_width_px,
        .ypixel = size.rows *| size.cell_height_px,
    };
}

/// How often a blocked read wakes to check whether close() asked it to stop.
const stop_poll_ms = 50;
/// Grace period for the shell to exit on SIGHUP before it is killed.
const hangup_grace_ms = 200;

pub const Child = struct {
    /// Master side of the pty: read the shell's output, write its input.
    fd: c_int,
    pid: c.pid_t,

    /// The login shell (configured, else $SHELL, else zsh) in `cwd`.
    pub fn start(gpa: std.mem.Allocator, options: pty.StartOptions) !Child {
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        const a = arena.allocator();
        const env_shell = if (c.getenv("SHELL")) |sh| std.mem.span(sh) else null;
        const shell = try a.dupeZ(u8, shell_env.resolveShell(options.shell, env_shell));
        const cwd = if (options.cwd) |dir| (try a.dupeZ(u8, dir)).ptr else null;
        const argv = try shell_env.loginArgv(a, shell);
        const envp = try shell_env.sessionEnv(a, try parentEnv(a));
        return spawn(shell.ptr, argv, envp, cwd, options.size);
    }

    /// The shell's output into `buf`: the count, or null once the shell
    /// closed its side or `stop` turned true.
    pub fn read(self: Child, buf: []u8, stop: *const std.atomic.Value(bool)) ?usize {
        var fds = [_]c.pollfd{.{ .fd = self.fd, .events = c.POLL.IN, .revents = 0 }};
        while (!stop.load(.acquire)) {
            if (c.poll(&fds, 1, stop_poll_ms) <= 0) continue;
            const n = c.read(self.fd, buf.ptr, buf.len);
            if (n < 0 and c.errno(n) == .INTR) continue;
            // 0 or EIO: the shell closed its side of the pty.
            if (n <= 0) return null;
            return @intCast(n);
        }
        return null;
    }

    pub fn write(self: Child, bytes: []const u8) error{WriteFailed}!void {
        var rest = bytes;
        while (rest.len > 0) {
            const n = c.write(self.fd, rest.ptr, rest.len);
            if (n < 0) {
                switch (c.errno(n)) {
                    .INTR, .AGAIN => continue,
                    else => return error.WriteFailed,
                }
            }
            rest = rest[@intCast(n)..];
        }
    }

    pub fn resize(self: Child, size: Size) error{ResizeFailed}!void {
        const ws = winsize(size);
        if (ioctl(self.fd, TIOCSWINSZ, &ws) != 0) return error.ResizeFailed;
    }

    /// True while a program other than the shell itself owns the terminal,
    /// such as an agent, a server or `sleep`. Used to confirm before closing.
    pub fn hasForegroundProcess(self: Child) bool {
        const group = tcgetpgrp(self.fd);
        return group > 0 and group != self.pid;
    }

    /// The foreground program's process group, 0 when the shell itself
    /// owns the terminal: the app matches an agent's pid to its terminal
    /// with it (docs/spec/agents.md).
    pub fn foregroundGroup(self: Child) i32 {
        const group = tcgetpgrp(self.fd);
        return if (group > 0 and group != self.pid) @intCast(group) else 0;
    }

    /// The current directory of the program in the foreground (the shell,
    /// or what it runs), written into `buf`. Null if the system does not
    /// say. Used when the shell does not report its directory with OSC 7.
    pub fn currentDirectory(self: Child, buf: *DirectoryBuffer) ?[]const u8 {
        const group = tcgetpgrp(self.fd);
        const pid = if (group > 0) group else self.pid;
        const got = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, buf, vnode_path_info_size);
        if (got != vnode_path_info_size) return null;
        const path = std.mem.sliceTo(buf[cwd_path_offset..], 0);
        return if (path.len == 0) null else path;
    }

    /// After read() gave null on its own: the shell's exit code.
    pub fn waitExitCode(self: Child) i32 {
        return waitPid(self.pid);
    }

    /// Nothing to do: the reader polls `stop`.
    pub fn unblockReader(self: Child) void {
        _ = self;
    }

    /// After the reader stopped: ends the shell (SIGHUP, then SIGKILL)
    /// unless it was reaped already, and frees the pty.
    pub fn finish(self: Child, reaped: bool) void {
        // Close our side of the pty before waiting for the shell. With the
        // reader stopped nobody drains its output, and an exiting shell
        // waits in the kernel for that drain: the app hung forever in
        // waitpid closing a tab that ran `sleep 100` (2026-10-19, sample of
        // the main thread in __wait4, zsh in state E).
        _ = c.close(self.fd);
        if (!reaped) hangUp(self, hangup_grace_ms);
    }

    /// A session that failed to open: kill the shell at once.
    pub fn kill(self: Child) void {
        _ = c.close(self.fd);
        killNow(self);
    }
};

fn parentEnv(arena: std.mem.Allocator) ![]const [*:0]const u8 {
    var list: std.ArrayList([*:0]const u8) = .empty;
    var i: usize = 0;
    while (c.environ[i]) |entry| : (i += 1) try list.append(arena, entry);
    return list.items;
}

/// $HOME, for links written as ~/path.
pub fn homeDirectory(buf: []u8) ?[]const u8 {
    _ = buf;
    return if (c.getenv("HOME")) |h| std.mem.span(h) else null;
}

pub const SpawnError = error{ForkFailed};

/// Starts `shell_path` as a login shell on a new pty. Everything the child
/// needs is prepared by the caller before the fork: after fork() in a
/// threaded process only async-signal-safe calls are allowed, so the child
/// does nothing but chdir and execve.
fn spawn(
    shell_path: [*:0]const u8,
    argv: shell_env.Argv,
    envp: shell_env.Envp,
    cwd: ?[*:0]const u8,
    size: Size,
) SpawnError!Child {
    var fd: c_int = undefined;
    const ws = winsize(size);
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

pub const DirectoryBuffer = [vnode_path_info_size]u8;

fn waitPid(pid: c.pid_t) i32 {
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
fn hangUp(child: Child, grace_ms: u32) void {
    _ = c.kill(child.pid, .HUP);
    var waited: u32 = 0;
    while (waited < grace_ms) : (waited += 10) {
        if (c.waitpid(child.pid, null, c.W.NOHANG) != 0) return;
        clock.sleepMs(10);
    }
    killNow(child);
}

/// How long close() waits for a killed shell before reaping it in the
/// background instead: closing must never hang the app.
const kill_wait_ms = 500;

fn killNow(child: Child) void {
    _ = c.kill(child.pid, .KILL);
    var waited: u32 = 0;
    while (waited < kill_wait_ms) : (waited += 10) {
        if (c.waitpid(child.pid, null, c.W.NOHANG) != 0) return;
        clock.sleepMs(10);
    }
    // Still exiting: reap it on a thread of its own so it does not stay a
    // zombie, without blocking the caller.
    const reaper = std.Thread.spawn(.{}, reapBlocking, .{child.pid}) catch return;
    reaper.detach();
}

fn reapBlocking(pid: c.pid_t) void {
    _ = waitPid(pid);
}

test "exit status decoding follows the shell convention" {
    try std.testing.expectEqual(@as(i32, 0), decodeStatus(0));
    try std.testing.expectEqual(@as(i32, 3), decodeStatus(3 << 8));
    try std.testing.expectEqual(@as(i32, 128 + 9), decodeStatus(9));
}
