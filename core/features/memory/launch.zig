//! Starting `cadex-memory` on demand, as the terminal daemon is started
//! (core/features/terminal/daemon_client.zig, `ensure`; no launchd, ADR
//! 0022): connect first; if nothing answers, spawn the engine in its own
//! session (SETSID) with no descriptor of ours and its output to /dev/null,
//! and poll the socket every 20 ms until the deadline. Only SessionStart
//! does this (plan 22: "nunca espera o engine fora do SessionStart"), within
//! its 1 s. The hook exits right after, so launchd adopts and reaps the
//! engine; no reaper thread is needed here.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const http = @import("http.zig");
const c = std.c;

/// What the engine is started with (the kit's environment).
pub const Engine = struct {
    bin: [:0]const u8,
    socket: [:0]const u8,
    data_dir: [:0]const u8,
    /// Passed only when the kit names one (CADEX_SESSIONS_DIR); else the
    /// engine's default, the app's tokens folder.
    tokens_dir: ?[:0]const u8 = null,
};

/// The engine's arguments, for `posix_spawn`.
pub fn argv(engine: Engine, out: *[9:null]?[*:0]const u8) [*:null]const ?[*:0]const u8 {
    out.* = .{ engine.bin.ptr, "--socket", engine.socket.ptr, "--data-dir", engine.data_dir.ptr, null, null, null, null };
    if (engine.tokens_dir) |dir| {
        out[5] = "--tokens-dir";
        out[6] = dir.ptr;
    }
    return out;
}

fn answers(socket: []const u8) bool {
    const fd = http.connect(socket) orelse return false;
    _ = c.close(fd);
    return true;
}

fn spawn(engine: Engine) bool {
    var actions: c.posix_spawn_file_actions_t = undefined;
    if (c.posix_spawn_file_actions_init(&actions) != 0) return false;
    defer _ = c.posix_spawn_file_actions_destroy(&actions);
    for ([_]c_int{ 0, 1, 2 }) |fd| _ = c.posix_spawn_file_actions_addopen(&actions, fd, "/dev/null", @as(c_int, @bitCast(c.O{ .ACCMODE = .RDWR })), 0);
    var attr: c.posix_spawnattr_t = undefined;
    if (c.posix_spawnattr_init(&attr) != 0) return false;
    defer _ = c.posix_spawnattr_destroy(&attr);
    _ = c.posix_spawnattr_setflags(&attr, .{ .SETSID = true, .CLOEXEC_DEFAULT = true });
    var args: [9:null]?[*:0]const u8 = undefined;
    var pid: c.pid_t = 0;
    return c.posix_spawn(&pid, engine.bin.ptr, &actions, &attr, argv(engine, &args), c.environ) == 0;
}

/// Whether the engine answers on its socket by `deadline_ms`
/// (clock.monotonicMs), starting it if it does not.
pub fn ensure(engine: Engine, deadline_ms: i64) bool {
    if (answers(engine.socket)) return true;
    if (!spawn(engine)) return false;
    while (clock.monotonicMs() < deadline_ms) {
        clock.sleepMs(20);
        if (answers(engine.socket)) return true;
    }
    return false;
}

const testing = std.testing;

test "the engine gets its socket and folder, and the tokens folder only when named" {
    var out: [9:null]?[*:0]const u8 = undefined;
    const plain = argv(.{ .bin = "/b/cadex-memory", .socket = "/s.sock", .data_dir = "/m" }, &out);
    try testing.expectEqualStrings("--data-dir", std.mem.span(plain[3].?));
    try testing.expect(plain[5] == null);
    const named = argv(.{ .bin = "/b/cadex-memory", .socket = "/s.sock", .data_dir = "/m", .tokens_dir = "/t" }, &out);
    try testing.expectEqualStrings("--tokens-dir", std.mem.span(named[5].?));
    try testing.expectEqualStrings("/t", std.mem.span(named[6].?));
}

test "a missing engine binary gives up without waiting" {
    const start = clock.monotonicMs();
    try testing.expect(!ensure(.{ .bin = "/nonexistent/cadex-memory", .socket = "/nonexistent/m.sock", .data_dir = "/nonexistent" }, start + 1000));
    try testing.expect(clock.monotonicMs() - start < 500);
}
