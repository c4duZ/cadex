//! `cadex memory-hook <event>`: the memory's hook in the sessions Cadex
//! opens (plan 22, phase C). It reads the hook's JSON and posts it to the
//! engine on memory.sock with the session's token. SessionStart starts the
//! engine if it is down, waits for it at most 1 s, and prints the briefing
//! as `additionalContext`; every other event gets 200 ms, and if the engine
//! does not take it, the event goes to the queue (spool.zig) and the hook
//! leaves. Nothing here makes the session fail: no token, no engine or any
//! error means printing nothing.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const events = @import("events.zig");
const http = @import("http.zig");
const launch = @import("launch.zig");
const spool = @import("spool.zig");

extern "c" fn getppid() c_int;

/// SessionStart's whole budget (start the engine, post, fetch the briefing).
pub const start_budget_ms = 1000;
/// Any other event's: past this the event waits in the queue.
pub const event_budget_ms = 200;

/// What the kit's environment says (SessionKit in the app).
pub const Env = struct {
    token: []const u8,
    socket: [:0]const u8,
    data_dir: [:0]const u8,
    /// The `cadex-memory` binary; without it the engine cannot be started.
    bin: ?[:0]const u8 = null,
    tokens_dir: ?[:0]const u8 = null,

    pub const Lookup = *const fn ([*:0]const u8) ?[:0]const u8;

    /// From the environment `getenv` reads; null without a session token (a
    /// session Cadex did not open, or memory off: nothing to do).
    pub fn from(getenv: Lookup, socket_buf: *[256]u8, dir_buf: *[1024]u8) ?Env {
        const token = getenv("CADEX_SESSION_TOKEN") orelse return null;
        const home = getenv("HOME") orelse "";
        const support = "Library/Application Support/Cadex";
        return .{
            .token = token,
            .socket = getenv("CADEX_MEMORY_SOCKET") orelse
                (std.fmt.bufPrintZ(socket_buf, "{s}/{s}/sockets/memory.sock", .{ home, support }) catch return null),
            .data_dir = getenv("CADEX_MEMORY_DIR") orelse
                (std.fmt.bufPrintZ(dir_buf, "{s}/{s}/memory", .{ home, support }) catch return null),
            .bin = getenv("CADEX_MEMORY_BIN"),
            .tokens_dir = getenv("CADEX_SESSIONS_DIR"),
        };
    }

    pub fn processEnv(name: [*:0]const u8) ?[:0]const u8 {
        const value = std.mem.span(std.c.getenv(name) orelse return null);
        return if (value.len > 0) value else null;
    }
};

/// The briefing without the engine's backfill marker line (an HTML comment
/// for upstream's own client, `extract_backfill_marker` in its hook.rs; the
/// agent must not see it), trimmed. Empty when there is nothing to say.
pub fn briefingText(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "<!-- ai-memory:backfill ")) continue;
        try out.appendSlice(gpa, line);
        try out.append(gpa, '\n');
    }
    const trimmed = std.mem.trim(u8, out.items, " \t\r\n");
    const result = try gpa.dupe(u8, trimmed);
    out.deinit(gpa);
    return result;
}

/// What Claude Code takes from a SessionStart hook as context (the shape
/// of upstream's `session_start_handoff_envelope` for claude-code).
pub fn startOutput(gpa: std.mem.Allocator, briefing: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"hookSpecificOutput\":{{\"hookEventName\":\"SessionStart\",\"additionalContext\":{f}}}}}\n", .{
        std.json.fmt(briefing, .{}),
    });
}

/// The whole command: the hook's JSON in, what to print out (maybe nothing).
pub fn run(gpa: std.mem.Allocator, claude_event: []const u8, input: []const u8) !?[]u8 {
    var socket_buf: [256]u8 = undefined;
    var dir_buf: [1024]u8 = undefined;
    const env = Env.from(Env.processEnv, &socket_buf, &dir_buf) orelse return null;
    return runWith(gpa, env, claude_event, input, getppid());
}

/// `run` with the environment and the `claude` pid given (tests).
pub fn runWith(gpa: std.mem.Allocator, env: Env, claude_event: []const u8, input: []const u8, claude_pid: c_int) !?[]u8 {
    const started = clock.monotonicMs();
    const event = events.engineEvent(claude_event) orelse return null;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, input, .{}) catch null;
    defer if (parsed) |*p| p.deinit();
    const payload = events.Payload.of(if (parsed) |p| p.value else .null);
    var key_buf: [32]u8 = undefined;
    const pid: ?c_int = if (events.sendsPid(event)) claude_pid else null;
    const target = try events.hookTarget(gpa, event, payload, events.ingestKey(&key_buf), pid);
    defer gpa.free(target);

    const is_start = std.mem.eql(u8, event, "session-start");
    const deadline = started + @as(i64, if (is_start) start_budget_ms else event_budget_ms);
    if (is_start) if (env.bin) |bin| {
        _ = launch.ensure(.{ .bin = bin, .socket = env.socket, .data_dir = env.data_dir, .tokens_dir = env.tokens_dir }, deadline);
    };
    const posted = try http.send(gpa, env.socket, "POST", target, env.token, input, deadline);
    if (posted) |answer| {
        defer answer.deinit(gpa);
        // A refusal (bad token, bad request) would be refused again later.
        if (answer.status >= 500) spool.write(gpa, env.data_dir, target, input) catch {};
    } else {
        spool.write(gpa, env.data_dir, target, input) catch {};
        return null;
    }
    if (!is_start) return null;
    return fetchBriefing(gpa, env, payload, deadline);
}

fn fetchBriefing(gpa: std.mem.Allocator, env: Env, payload: events.Payload, deadline: i64) !?[]u8 {
    const target = try events.handoffTarget(gpa, payload);
    defer gpa.free(target);
    const answer = (try http.send(gpa, env.socket, "GET", target, env.token, "", deadline)) orelse return null;
    defer answer.deinit(gpa);
    if (!answer.ok()) return null;
    const text = try briefingText(gpa, answer.body);
    defer gpa.free(text);
    if (text.len == 0) return null;
    return try startOutput(gpa, text);
}

const testing = std.testing;

test "the briefing loses the backfill marker and becomes additionalContext" {
    const text = try briefingText(testing.allocator, "\n# Briefing\n<!-- ai-memory:backfill session_id=x agent_kind=claude-code -->\nUse \"tabs\".\n\n");
    defer testing.allocator.free(text);
    try testing.expectEqualStrings("# Briefing\nUse \"tabs\".", text);
    const out = try startOutput(testing.allocator, text);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"# Briefing\\nUse \\\"tabs\\\".\"}}\n", out);
    const empty = try briefingText(testing.allocator, " \n<!-- ai-memory:backfill x -->\n");
    defer testing.allocator.free(empty);
    try testing.expectEqual(@as(usize, 0), empty.len);
}

fn testEnv(name: [*:0]const u8) ?[:0]const u8 {
    const key = std.mem.span(name);
    if (std.mem.eql(u8, key, "HOME")) return "/Users/u";
    if (std.mem.eql(u8, key, "CADEX_SESSION_TOKEN")) return "tok";
    return null;
}

fn noTokenEnv(name: [*:0]const u8) ?[:0]const u8 {
    return if (std.mem.eql(u8, std.mem.span(name), "HOME")) "/Users/u" else null;
}

test "no session token, nothing to do; otherwise Cadex's folders by default" {
    var socket_buf: [256]u8 = undefined;
    var dir_buf: [1024]u8 = undefined;
    try testing.expect(Env.from(noTokenEnv, &socket_buf, &dir_buf) == null);
    const env = Env.from(testEnv, &socket_buf, &dir_buf).?;
    try testing.expectEqualStrings("tok", env.token);
    try testing.expectEqualStrings("/Users/u/Library/Application Support/Cadex/sockets/memory.sock", env.socket);
    try testing.expectEqualStrings("/Users/u/Library/Application Support/Cadex/memory", env.data_dir);
    try testing.expect(env.bin == null and env.tokens_dir == null);
}

test "an event the memory does not take does nothing" {
    const env: Env = .{ .token = "t", .socket = "/nonexistent/m.sock", .data_dir = "/nonexistent/memory" };
    try testing.expect(try runWith(testing.allocator, env, "PermissionRequest", "{}", 1) == null);
}

test "with the engine down an event is queued and the hook does not wait" {
    var tmp = try @import("../../shared/test_dir.zig").TestDir.init();
    defer tmp.deinit();
    var dir_buf: [1024]u8 = undefined;
    const data_dir = try std.fmt.bufPrintZ(&dir_buf, "{s}/memory", .{tmp.path()});
    const env: Env = .{ .token = "t", .socket = "/nonexistent/m.sock", .data_dir = data_dir };
    const start = clock.monotonicMs();
    try testing.expect(try runWith(testing.allocator, env, "PostToolUse", "{\"cwd\":\"/p\",\"session_id\":\"s\"}", 7) == null);
    try testing.expect(clock.monotonicMs() - start < event_budget_ms);
    var spool_buf: [1024]u8 = undefined;
    var reader = try @import("../../shared/fs.zig").DirReader.open(try std.fmt.bufPrint(&spool_buf, "{s}/spool", .{data_dir}));
    defer reader.close();
    try testing.expect(reader.next() != null);
}
