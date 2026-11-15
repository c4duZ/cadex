//! A command request from the agent to the Cadex app (docs/adr/0024-agent-tools.md):
//! `cadex run`, its shortcuts and the MCP server all end here. One line to
//! the app's socket, with the session's token (CADEX_SESSION_TOKEN, from the
//! kit's settings `env`) and the pids above this process, so the app finds
//! the terminal of the agent that asked; one line back:
//! `{"ok":true,"result":"…"}` or `{"ok":false,"error":"…"}`.

const std = @import("std");
const hook = @import("hook.zig");

/// A command may wait on the page (a navigation, a selector): long enough
/// for those, short of a hung app holding the agent forever.
pub const wait_ms: u32 = 40_000;

pub const Arg = struct { key: []const u8, value: []const u8 };

pub const Reply = struct {
    ok: bool,
    /// The result or the error, as the app wrote it.
    text: []u8,
    /// The answer line as it came (for --json).
    raw: []u8,

    pub fn deinit(self: Reply, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        gpa.free(self.raw);
    }
};

pub const Failure = error{ NoToken, NotRunning };

/// The line for running `id` with `args`, or for the list (`id` null).
pub fn line(gpa: std.mem.Allocator, token: []const u8, id: ?[]const u8, args: []const Arg, pids: []const c_int) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.print(gpa, "{{\"v\":1,\"token\":{f}", .{std.json.fmt(token, .{})});
    if (id) |name| {
        try out.print(gpa, ",\"run\":{f},\"args\":{{", .{std.json.fmt(name, .{})});
        for (args, 0..) |arg, i| {
            if (i > 0) try out.append(gpa, ',');
            try out.print(gpa, "{f}:{f}", .{ std.json.fmt(arg.key, .{}), std.json.fmt(arg.value, .{}) });
        }
        try out.append(gpa, '}');
    } else try out.appendSlice(gpa, ",\"list\":true");
    try out.appendSlice(gpa, ",\"pids\":[");
    for (pids, 0..) |pid, i| {
        if (i > 0) try out.append(gpa, ',');
        try out.print(gpa, "{d}", .{pid});
    }
    try out.appendSlice(gpa, "]}\n");
    return out.toOwnedSlice(gpa);
}

/// The app's answer read; a line that is not the expected JSON is a failure
/// with the line as its text.
pub fn parse(gpa: std.mem.Allocator, answer: []const u8) !Reply {
    const raw = try gpa.dupe(u8, std.mem.trimEnd(u8, answer, "\n"));
    errdefer gpa.free(raw);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{}) catch
        return .{ .ok = false, .text = try gpa.dupe(u8, raw), .raw = raw };
    defer parsed.deinit();
    const object = if (parsed.value == .object) parsed.value.object else
        return .{ .ok = false, .text = try gpa.dupe(u8, raw), .raw = raw };
    const ok = if (object.get("ok")) |v| v == .bool and v.bool else false;
    const field = object.get(if (ok) "result" else "error");
    const text = if (field) |v| (if (v == .string) v.string else "") else "";
    return .{ .ok = ok, .text = try gpa.dupe(u8, text), .raw = raw };
}

/// mcp.zig's way to run a command (its tools always name one).
pub fn sendCommand(gpa: std.mem.Allocator, id: []const u8, args: []const Arg) anyerror!Reply {
    return send(gpa, id, args);
}

/// Sends the request and waits for the answer.
pub fn send(gpa: std.mem.Allocator, id: ?[]const u8, args: []const Arg) !Reply {
    const token = std.mem.span(std.c.getenv("CADEX_SESSION_TOKEN") orelse return error.NoToken);
    if (token.len == 0) return error.NoToken;
    var path_buf: [256]u8 = undefined;
    const path = hook.socketPath(&path_buf) orelse return error.NotRunning;
    var pids_buf: [12]c_int = undefined;
    const msg = try line(gpa, token, id, args, ancestors(&pids_buf));
    defer gpa.free(msg);
    const answer = (try hook.exchange(gpa, path, msg, wait_ms)) orelse return error.NotRunning;
    defer gpa.free(answer);
    return parse(gpa, answer);
}

// <sys/proc_info.h>: PROC_PIDTBSDINFO and struct proc_bsdinfo, whose
// pbi_ppid is at byte 16 of 136 (measured with clang, 2026-11-15).
extern "c" fn proc_pidinfo(pid: c_int, flavor: c_int, arg: u64, buffer: ?*anyopaque, size: c_int) c_int;
extern "c" fn getppid() c_int;
extern "c" fn getpid() c_int;
const PROC_PIDTBSDINFO: c_int = 3;
const bsdinfo_size = 136;
const ppid_offset = 16;

/// This process, its parent, its parent and so on, up to launchd or
/// `out`'s size: the agent's `claude` is one of them (its Bash tool runs a
/// shell), or, typed at a terminal's shell, `cadex` itself leads the
/// terminal's foreground group (found 2026-11-15).
pub fn ancestors(out: []c_int) []const c_int {
    var n: usize = 0;
    var pid = getpid();
    while (pid > 1 and n < out.len) {
        out[n] = pid;
        n += 1;
        var info: [bsdinfo_size]u8 align(8) = undefined;
        if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, bsdinfo_size) != bsdinfo_size) break;
        pid = std.mem.readInt(c_int, info[ppid_offset..][0..4], .little);
    }
    return out[0..n];
}

const testing = std.testing;

test "the request line names the command, its arguments and the pids above" {
    const msg = try line(testing.allocator, "tok", "agent-tools.notify", &.{.{ .key = "text", .value = "oi \"x\"" }}, &.{ 7, 3 });
    defer testing.allocator.free(msg);
    try testing.expectEqualStrings("{\"v\":1,\"token\":\"tok\",\"run\":\"agent-tools.notify\",\"args\":{\"text\":\"oi \\\"x\\\"\"},\"pids\":[7,3]}\n", msg);
    const list = try line(testing.allocator, "tok", null, &.{}, &.{});
    defer testing.allocator.free(list);
    try testing.expectEqualStrings("{\"v\":1,\"token\":\"tok\",\"list\":true,\"pids\":[]}\n", list);
}

test "the app's answer: the result, the error, or a line that is not JSON" {
    const ok = try parse(testing.allocator, "{\"ok\":true,\"result\":\"opened\"}\n");
    defer ok.deinit(testing.allocator);
    try testing.expect(ok.ok);
    try testing.expectEqualStrings("opened", ok.text);
    const no = try parse(testing.allocator, "{\"ok\":false,\"error\":\"not allowed for agents\"}");
    defer no.deinit(testing.allocator);
    try testing.expect(!no.ok);
    try testing.expectEqualStrings("not allowed for agents", no.text);
    const odd = try parse(testing.allocator, "garbage");
    defer odd.deinit(testing.allocator);
    try testing.expect(!odd.ok and std.mem.eql(u8, odd.text, "garbage"));
}

test "the pids start with this process, then its parent" {
    var buf: [12]c_int = undefined;
    const pids = ancestors(&buf);
    try testing.expect(pids.len >= 2 and pids[0] == getpid() and pids[1] == getppid());
}
