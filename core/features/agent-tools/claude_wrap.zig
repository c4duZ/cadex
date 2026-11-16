//! `cadex claude <args…>`: what the `claude` typed in a Cadex zsh tab runs
//! (the shell function of the terminal's zsh integration, plan 22 phase C).
//! An interactive session asks the app for the session kit over app.sock
//! and runs the real `claude` with it; everything else, and any failure
//! (no app, refused, a bad answer), runs the real `claude` exactly as
//! typed: the owner's command never breaks. The account is the tab's:
//! CLAUDE_CONFIG_DIR is never changed.
//!
//! No session token exists in a tab: the app takes the request only from a
//! process under the shell of one of its own terminals (it walks the
//! connecting process's ancestry itself) and of this user (getpeereid).

const std = @import("std");
const claude_args = @import("claude_args.zig");
const hook = @import("hook.zig");
const request = @import("request.zig");

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
extern "c" fn access(path: [*:0]const u8, mode: c_int) c_int;
extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;
extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn _NSGetExecutablePath(buf: [*]u8, size: *u32) c_int;
extern "c" fn getpid() c_int;
extern "c" fn getppid() c_int;
extern "c" var environ: [*:null]?[*:0]u8;

/// The app writes the kit's files and answers at once; a hung app must not
/// hold the owner's `claude` for long.
pub const wait_ms: u32 = 3_000;
const X_OK: c_int = 1;
const path_max = 1024;

/// Marks the `claude` this process became (exec keeps the pid): if that
/// `claude` is a script that runs `cadex claude` again, the second one
/// sees its own pid, or its parent's, and stops instead of looping.
const loop_mark = "CADEX_CLAUDE_WRAP";

/// The kit as the app sent it: words to put before the owner's, names to
/// drop from the environment, a folder to put first on PATH.
pub const Kit = struct {
    ok: bool = false,
    args: []const []const u8 = &.{},
    unset: []const []const u8 = &.{},
    path_first: ?[]const u8 = null,
};

/// The request line: the pids above this process (the app checks the
/// ancestry on its side too), the tab's account and folder, the owner's
/// own `--settings` (merged with the kit's into one file) and the words
/// (kept beside the session's token, for a hibernated agent to come back).
pub fn line(gpa: std.mem.Allocator, pids: []const c_int, config_dir: []const u8, cwd: []const u8, user_settings: ?[]const u8, words: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "{\"v\":1,\"kit\":true,\"pids\":[");
    for (pids, 0..) |pid, i| {
        if (i > 0) try out.append(gpa, ',');
        try out.print(gpa, "{d}", .{pid});
    }
    try out.print(gpa, "],\"config_dir\":{f},\"cwd\":{f},\"user_settings\":", .{ std.json.fmt(config_dir, .{}), std.json.fmt(cwd, .{}) });
    if (user_settings) |s| try out.print(gpa, "{f}", .{std.json.fmt(s, .{})}) else try out.appendSlice(gpa, "null");
    try out.print(gpa, ",\"args\":{f}}}\n", .{std.json.fmt(words, .{})});
    return out.toOwnedSlice(gpa);
}

/// The app's answer; null when it refused or the line does not read.
pub fn parseKit(arena: std.mem.Allocator, answer: []const u8) ?Kit {
    const kit = std.json.parseFromSliceLeaky(Kit, arena, std.mem.trimEnd(u8, answer, "\n"), .{ .ignore_unknown_fields = true }) catch return null;
    return if (kit.ok) kit else null;
}

/// Asks the app at `socket`; null for no app, a refusal or a bad answer.
pub fn askKit(arena: std.mem.Allocator, socket: []const u8, msg: []const u8) ?Kit {
    const answer = (hook.exchange(arena, socket, msg, wait_ms) catch return null) orelse return null;
    return parseKit(arena, answer);
}

/// The whole command. Returns only when `claude` could not be run.
pub fn run(words: []const [:0]const u8) u8 {
    var arena_state: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    if (looping()) return say("cadex claude: the claude on PATH runs `cadex claude` again\n");
    var real_buf: [path_max]u8 = undefined;
    const real = findReal(arena, &real_buf) orelse return say("cadex claude: claude is not on PATH\n");
    markLoop();
    const plain = toSlices(arena, words) catch return execAs(arena, real, &.{}, words);
    const p = claude_args.plan(arena, plain) catch return execAs(arena, real, &.{}, words);
    if (p == .pass_through) return execAs(arena, real, &.{}, words);
    const kit = kitFor(arena, p.kit.user_settings, p.kit.words) orelse return execAs(arena, real, &.{}, words);
    for (kit.unset) |name| _ = unsetenv((arena.dupeZ(u8, name) catch continue).ptr);
    if (kit.path_first) |dir| prependPath(arena, dir);
    const rest = toSentinels(arena, p.kit.words) catch return execAs(arena, real, &.{}, words);
    return execAs(arena, real, kit.args, rest);
}

/// The kit for this tab (also `cadex continue`, continue_wrap.zig).
pub fn kitFor(arena: std.mem.Allocator, user_settings: ?[]const u8, words: []const []const u8) ?Kit {
    var path_buf: [256]u8 = undefined;
    const socket = hook.socketPath(&path_buf) orelse return null;
    var pids_buf: [12]c_int = undefined;
    const config_dir = if (std.c.getenv("CLAUDE_CONFIG_DIR")) |v| std.mem.span(v) else "";
    var cwd_buf: [path_max]u8 = undefined;
    const cwd = if (getcwd(&cwd_buf, cwd_buf.len)) |p| std.mem.span(p) else "";
    const msg = line(arena, request.ancestors(&pids_buf), config_dir, cwd, user_settings, words) catch return null;
    return askKit(arena, socket, msg);
}

/// argv: "claude", the kit's words, then the owner's.
fn execAs(arena: std.mem.Allocator, real: [:0]const u8, kit_args: []const []const u8, words: []const [:0]const u8) u8 {
    var argv: std.ArrayList(?[*:0]const u8) = .empty;
    argv.append(arena, "claude") catch return 127;
    for (kit_args) |arg| argv.append(arena, (arena.dupeZ(u8, arg) catch return 127).ptr) catch return 127;
    for (words) |word| argv.append(arena, word.ptr) catch return 127;
    const list = argv.toOwnedSliceSentinel(arena, null) catch return 127;
    _ = execve(real.ptr, list.ptr, @ptrCast(environ));
    return say("cadex claude: claude did not start\n");
}

/// The first `claude` on PATH that is not this program (a `claude` linked
/// to `cadex` would run `cadex` again).
fn findReal(arena: std.mem.Allocator, out: *[path_max]u8) ?[:0]const u8 {
    var self_buf: [path_max]u8 = undefined;
    var self_raw: [path_max]u8 = undefined;
    var size: u32 = self_raw.len;
    const self: []const u8 = if (_NSGetExecutablePath(&self_raw, &size) == 0)
        if (realpath(@ptrCast(&self_raw), &self_buf)) |p| std.mem.span(p) else ""
    else
        "";
    const path = std.mem.span(std.c.getenv("PATH") orelse return null);
    var dirs = std.mem.splitScalar(u8, path, ':');
    while (dirs.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fmt.allocPrintSentinel(arena, "{s}/claude", .{dir}, 0) catch return null;
        if (access(candidate.ptr, X_OK) != 0) continue;
        const resolved = realpath(candidate.ptr, out) orelse continue;
        if (self.len > 0 and std.mem.eql(u8, std.mem.span(resolved), self)) continue;
        return candidate;
    }
    return null;
}

fn looping() bool {
    const mark = std.mem.span(std.c.getenv(loop_mark) orelse return false);
    const pid = std.fmt.parseInt(c_int, mark, 10) catch return false;
    return pid == getpid() or pid == getppid();
}

fn markLoop() void {
    var buf: [16]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d}", .{getpid()}) catch return;
    _ = setenv(loop_mark, text.ptr, 1);
}

fn prependPath(arena: std.mem.Allocator, dir: []const u8) void {
    const old = if (std.c.getenv("PATH")) |v| std.mem.span(v) else "";
    const value = std.fmt.allocPrintSentinel(arena, "{s}:{s}", .{ dir, old }, 0) catch return;
    _ = setenv("PATH", value.ptr, 1);
}

fn toSlices(arena: std.mem.Allocator, words: []const [:0]const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, words.len);
    for (words, out) |w, *o| o.* = w;
    return out;
}

fn toSentinels(arena: std.mem.Allocator, words: []const []const u8) ![]const [:0]const u8 {
    const out = try arena.alloc([:0]const u8, words.len);
    for (words, out) |w, *o| o.* = try arena.dupeZ(u8, w);
    return out;
}

fn say(text: []const u8) u8 {
    _ = std.c.write(2, text.ptr, text.len);
    return 127;
}

const testing = std.testing;

test "the kit request names the pids, the account, the folder, the owner's settings and words" {
    const msg = try line(testing.allocator, &.{ 9, 4 }, "/Users/c/.claude-w", "/repo", "{\"a\":1}", &.{ "--resume", "x" });
    defer testing.allocator.free(msg);
    try testing.expectEqualStrings("{\"v\":1,\"kit\":true,\"pids\":[9,4],\"config_dir\":\"/Users/c/.claude-w\",\"cwd\":\"/repo\"," ++
        "\"user_settings\":\"{\\\"a\\\":1}\",\"args\":[\"--resume\",\"x\"]}\n", msg);
    const none = try line(testing.allocator, &.{}, "", "/", null, &.{});
    defer testing.allocator.free(none);
    try testing.expect(std.mem.indexOf(u8, none, "\"user_settings\":null,\"args\":[]}") != null);
}

test "the app's answer: the kit's words, names to drop and PATH; a refusal is no kit" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const kit = parseKit(arena, "{\"ok\":true,\"args\":[\"--settings\",\"/k/s.json\"],\"unset\":[\"CLAUDECODE\"],\"path_first\":\"/H\"}\n").?;
    try testing.expectEqual(@as(usize, 2), kit.args.len);
    try testing.expectEqualStrings("/k/s.json", kit.args[1]);
    try testing.expectEqualStrings("CLAUDECODE", kit.unset[0]);
    try testing.expectEqualStrings("/H", kit.path_first.?);
    try testing.expect(parseKit(arena, "{\"ok\":false,\"error\":\"not a Cadex terminal\"}") == null);
    try testing.expect(parseKit(arena, "garbage") == null);
    try testing.expect(parseKit(arena, "{\"ok\":true}").?.args.len == 0);
}

test "no app on the socket: no kit, so claude runs as typed" {
    var arena_state: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena_state.deinit();
    try testing.expect(askKit(arena_state.allocator(), "/nonexistent/cadex-test/app.sock", "{}\n") == null);
}
