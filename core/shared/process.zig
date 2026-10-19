//! Runs a program and collects what it prints (docs/plans/6-git.md): no
//! shell (arguments as given), a working folder, a time limit, a limit on
//! output, and extra environment variables. Used by source-control and
//! git-history to run the user's `git`. The terminal's shell is a PTY, not
//! this.

const std = @import("std");
const c = std.c;

pub const Options = struct {
    cwd: ?[]const u8 = null,
    /// The program is killed (with its process group) after this long.
    timeout_ms: u32 = 30_000,
    /// Bytes kept of each of stdout and stderr; the rest is read and dropped.
    max_output: usize = 16 * 1024 * 1024,
    /// "NAME=value" added to the app's environment (later ones win).
    env: []const []const u8 = &.{},
    /// Bytes written to the program's stdin, then closed. Empty: /dev/null.
    stdin: []const u8 = "",
};

pub const Result = struct {
    /// Exit code; 128 + signal when killed; -1 when it could not start.
    code: i32,
    stdout: []u8,
    stderr: []u8,
    timed_out: bool,
    truncated: bool,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.stdout);
        gpa.free(self.stderr);
    }

    pub fn ok(self: Result) bool {
        return self.code == 0 and !self.timed_out;
    }
};

extern "c" fn posix_spawnattr_setpgroup(attr: *c.posix_spawnattr_t, pgroup: c.pid_t) c_int;

pub fn run(gpa: std.mem.Allocator, argv: []const []const u8, options: Options) !Result {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const args = try a.allocSentinel(?[*:0]const u8, argv.len, null);
    for (argv, args) |arg, *slot| slot.* = (try a.dupeZ(u8, arg)).ptr;
    const env = try environment(a, options.env);

    var out_pipe: [2]c.fd_t = undefined;
    var err_pipe: [2]c.fd_t = undefined;
    var in_pipe: [2]c.fd_t = undefined;
    if (c.pipe(&out_pipe) != 0) return error.SpawnFailed;
    defer closeBoth(out_pipe);
    if (c.pipe(&err_pipe) != 0) return error.SpawnFailed;
    defer closeBoth(err_pipe);
    if (c.pipe(&in_pipe) != 0) return error.SpawnFailed;
    defer closeBoth(in_pipe);

    var actions: c.posix_spawn_file_actions_t = undefined;
    if (c.posix_spawn_file_actions_init(&actions) != 0) return error.SpawnFailed;
    defer _ = c.posix_spawn_file_actions_destroy(&actions);
    _ = c.posix_spawn_file_actions_adddup2(&actions, in_pipe[0], 0);
    _ = c.posix_spawn_file_actions_adddup2(&actions, out_pipe[1], 1);
    _ = c.posix_spawn_file_actions_adddup2(&actions, err_pipe[1], 2);
    if (options.cwd) |dir| _ = c.posix_spawn_file_actions_addchdir_np(&actions, (try a.dupeZ(u8, dir)).ptr);

    var attr: c.posix_spawnattr_t = undefined;
    if (c.posix_spawnattr_init(&attr) != 0) return error.SpawnFailed;
    defer _ = c.posix_spawnattr_destroy(&attr);
    // Only the three standard descriptors reach the child, and it leads its
    // own process group so a timeout kills what it started too (ssh).
    _ = c.posix_spawnattr_setflags(&attr, .{ .CLOEXEC_DEFAULT = true, .SETPGROUP = true });
    _ = posix_spawnattr_setpgroup(&attr, 0);

    var pid: c.pid_t = 0;
    if (c.posix_spawnp(&pid, args[0].?, &actions, &attr, args, env) != 0) {
        return .{ .code = -1, .stdout = try gpa.alloc(u8, 0), .stderr = try gpa.dupe(u8, "program not found"), .timed_out = false, .truncated = false };
    }
    // Our copies of the child's ends: closed so EOF arrives when it exits.
    _ = c.close(out_pipe[1]);
    out_pipe[1] = -1;
    _ = c.close(err_pipe[1]);
    err_pipe[1] = -1;
    _ = c.close(in_pipe[0]);
    in_pipe[0] = -1;
    if (options.stdin.len > 0) _ = c.write(in_pipe[1], options.stdin.ptr, options.stdin.len);
    _ = c.close(in_pipe[1]);
    in_pipe[1] = -1;

    var collected = try collect(gpa, out_pipe[0], err_pipe[0], pid, options);
    errdefer collected.deinit(gpa);
    collected.code = waitCode(pid);
    return collected;
}

fn closeBoth(fds: [2]c.fd_t) void {
    for (fds) |fd| if (fd >= 0) {
        _ = c.close(fd);
    };
}

/// Reads both pipes until EOF or the deadline; kills the group then.
fn collect(gpa: std.mem.Allocator, out_fd: c.fd_t, err_fd: c.fd_t, pid: c.pid_t, options: Options) !Result {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var err: std.ArrayList(u8) = .empty;
    errdefer err.deinit(gpa);
    var fds = [_]c.pollfd{
        .{ .fd = out_fd, .events = c.POLL.IN, .revents = 0 },
        .{ .fd = err_fd, .events = c.POLL.IN, .revents = 0 },
    };
    const deadline = nowMs() + options.timeout_ms;
    var truncated = false;
    var timed_out = false;
    var open: usize = 2;
    var buf: [64 * 1024]u8 = undefined;
    while (open > 0) {
        const left = deadline - nowMs();
        if (left <= 0) {
            timed_out = true;
            _ = c.kill(-pid, .KILL);
            break;
        }
        if (c.poll(&fds, fds.len, @intCast(@min(left, 1000))) <= 0) continue;
        for (&fds, 0..) |*p, i| {
            if (p.fd < 0 or p.revents == 0) continue;
            const n = c.read(p.fd, &buf, buf.len);
            if (n <= 0) {
                p.fd = -1;
                open -= 1;
                continue;
            }
            const list = if (i == 0) &out else &err;
            const room = options.max_output -| list.items.len;
            const keep = @min(room, @as(usize, @intCast(n)));
            if (keep < n) truncated = true;
            try list.appendSlice(gpa, buf[0..keep]);
        }
    }
    return .{ .code = 0, .stdout = try out.toOwnedSlice(gpa), .stderr = try err.toOwnedSlice(gpa), .timed_out = timed_out, .truncated = truncated };
}

fn waitCode(pid: c.pid_t) i32 {
    var status: c_int = 0;
    while (c.waitpid(pid, &status, 0) < 0) {
        if (std.c._errno().* != @intFromEnum(c.E.INTR)) return -1;
    }
    const s: u32 = @bitCast(status);
    if (s & 0x7f == 0) return @intCast((s >> 8) & 0xff);
    return 128 + @as(i32, @intCast(s & 0x7f));
}

/// The app's environment plus `extra`, an entry replaced when named again.
fn environment(a: std.mem.Allocator, extra: []const []const u8) ![*:null]const ?[*:0]const u8 {
    var list: std.ArrayList(?[*:0]const u8) = .empty;
    var i: usize = 0;
    while (c.environ[i]) |entry| : (i += 1) {
        const text = std.mem.span(entry);
        const name = text[0 .. std.mem.indexOfScalar(u8, text, '=') orelse text.len];
        const replaced = for (extra) |e| {
            if (std.mem.startsWith(u8, e, name) and e.len > name.len and e[name.len] == '=') break true;
        } else false;
        if (!replaced) try list.append(a, entry);
    }
    for (extra) |e| try list.append(a, (try a.dupeZ(u8, e)).ptr);
    return (try list.toOwnedSliceSentinel(a, null)).ptr;
}

fn nowMs() i64 {
    var ts: c.timespec = undefined;
    _ = c.clock_gettime(.MONOTONIC, &ts);
    return @as(i64, ts.sec) * 1000 + @divTrunc(@as(i64, ts.nsec), 1_000_000);
}

const testing = std.testing;

test "runs without a shell, in a folder, with extra environment" {
    var r = try run(testing.allocator, &.{ "/bin/sh", "-c", "pwd; echo \"$CADEX_TEST\"; echo oops >&2; exit 3" }, .{
        .cwd = "/usr",
        .env = &.{"CADEX_TEST=a b"},
    });
    defer r.deinit(testing.allocator);
    try testing.expectEqual(@as(i32, 3), r.code);
    try testing.expectEqualStrings("/usr\na b\n", r.stdout);
    try testing.expectEqualStrings("oops\n", r.stderr);
}

test "stdin, output limit, and a time limit that kills" {
    var cat = try run(testing.allocator, &.{"cat"}, .{ .stdin = "0123456789", .max_output = 4 });
    defer cat.deinit(testing.allocator);
    try testing.expectEqualStrings("0123", cat.stdout);
    try testing.expect(cat.truncated);
    var slow = try run(testing.allocator, &.{ "sleep", "5" }, .{ .timeout_ms = 200 });
    defer slow.deinit(testing.allocator);
    try testing.expect(slow.timed_out);
    try testing.expect(!slow.ok());
    var missing = try run(testing.allocator, &.{"cadex-no-such-program"}, .{});
    defer missing.deinit(testing.allocator);
    try testing.expectEqual(@as(i32, -1), missing.code);
}
