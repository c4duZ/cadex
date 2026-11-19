//! `cadex memory-hook <event>`: the memory's hook in the sessions Cadex
//! opens (plan 22, phase C). It reads the hook's JSON and posts it to the
//! engine on memory.sock with the session's token. SessionStart starts the
//! engine if it is down, waits for it at most 1 s, and prints the briefing
//! as `additionalContext`; every other event gets 200 ms, and if the engine
//! does not take it, the event goes to the queue (spool.zig) and the hook
//! leaves. Nothing here makes the session fail: no token, no engine or any
//! error means printing nothing.
//!
//! Besides the briefing, what upstream's own hook client hands back
//! (context.zig): the anchor after a compaction, the recap on "reload
//! context", and the brief a subagent starts with when the repository asks.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const events = @import("events.zig");
const consolidate = @import("consolidate.zig");
const context = @import("context.zig");
const http = @import("http.zig");
const launch = @import("launch.zig");
const spool = @import("spool.zig");

extern "c" fn getppid() c_int;

/// SessionStart's whole budget (start the engine, post, fetch the briefing).
pub const start_budget_ms = 1000;
/// Any other event's: past this the event waits in the queue.
pub const event_budget_ms = 200;
/// A hook that fetches something back for the session (the "reload context"
/// recap, a subagent's brief): it waits like SessionStart, but never starts
/// the engine (it is up: the session's SessionStart started it).
pub const fetch_budget_ms = start_budget_ms;

/// What the hook brings back after posting the event.
const Reply = enum { none, briefing, anchor, recap, brief, consolidate_stop, consolidate_asked };

fn replyFor(event: []const u8, payload: events.Payload) Reply {
    if (std.mem.eql(u8, event, "session-start")) {
        const compact = payload.source != null and std.mem.eql(u8, payload.source.?, "compact");
        if (!compact) return .briefing;
        return if (payload.agent_id == null and payload.session_id != null) .anchor else .none;
    }
    if (std.mem.eql(u8, event, "user-prompt-submit") and payload.session_id != null) {
        if (payload.prompt) |prompt| if (context.isReloadRequest(prompt)) return .recap;
    }
    if (std.mem.eql(u8, event, "subagent-start")) return .brief;
    return .none;
}

/// What the kit's environment says (SessionKit in the app).
pub const Env = struct {
    token: []const u8,
    socket: [:0]const u8,
    data_dir: [:0]const u8,
    /// The `cadex-memory` binary; without it the engine cannot be started.
    bin: ?[:0]const u8 = null,
    tokens_dir: ?[:0]const u8 = null,
    /// The account's own memory when memory.shareAcrossAccounts is off
    /// (CADEX_MEMORY_WORKSPACE, the account's key); null shares `default`.
    workspace: ?[:0]const u8 = null,
    /// A managed run's id and handoff switch (`cadex-memory run` sets them,
    /// as upstream's `ai-memory run` does; events.appendManaged).
    run_id: ?[:0]const u8 = null,
    auto_handoff: ?[:0]const u8 = null,
    /// Consolidation in the session (plan 22 phase F): the context percent
    /// that is a milestone (CADEX_MEMORY_CONSOLIDATE_AT, put by the kit with
    /// memory.consolidateInSession on; none: off) and where `cadex
    /// statusline` writes each session's context (CADEX_USAGE_DIR).
    consolidate_at: ?[:0]const u8 = null,
    usage_dir: ?[:0]const u8 = null,
    home: [:0]const u8 = "",

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
            .workspace = getenv("CADEX_MEMORY_WORKSPACE"),
            .run_id = getenv("AI_MEMORY_RUN_ID"),
            .auto_handoff = getenv("AI_MEMORY_AUTO_HANDOFF"),
            .consolidate_at = getenv("CADEX_MEMORY_CONSOLIDATE_AT"),
            .usage_dir = getenv("CADEX_USAGE_DIR"),
            .home = getenv("HOME") orelse "",
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
    const base = try events.hookTarget(gpa, event, payload, env.workspace, events.ingestKey(&key_buf), pid);
    var query: std.ArrayList(u8) = .fromOwnedSlice(base);
    defer query.deinit(gpa);
    try events.appendManaged(gpa, &query, env.run_id, env.auto_handoff, true);
    const target = query.items;

    const is_start = std.mem.eql(u8, event, "session-start");
    var reply = replyFor(event, payload);
    var milestone: consolidate.Reason = .asked;
    if (reply == .none) if (consolidationAt(env)) |threshold| {
        // Not on StopFailure: Claude Code ignores that hook's output, and the
        // milestone, once spent, would not ask again at the next Stop.
        if (std.mem.eql(u8, claude_event, "Stop")) {
            if (stopMilestone(gpa, env, payload, threshold)) |reason| {
                milestone = reason;
                reply = .consolidate_stop;
            }
        } else if (std.mem.eql(u8, event, "user-prompt-submit") and payload.session_id != null) {
            if (payload.prompt) |prompt| if (consolidate.isAsked(prompt)) {
                reply = .consolidate_asked;
            };
        }
    };
    const budget: i64 = if (is_start) start_budget_ms else if (reply != .none) fetch_budget_ms else event_budget_ms;
    const deadline = started + budget;
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
    return fetchReply(gpa, env, payload, reply, milestone, deadline);
}

/// The milestone percent, when consolidation in the session is on.
fn consolidationAt(env: Env) ?f64 {
    const raw = env.consolidate_at orelse return null;
    const value = std.fmt.parseFloat(f64, raw) catch return null;
    return if (value > 0 and value <= 100) value else null;
}

fn stopMilestone(gpa: std.mem.Allocator, env: Env, payload: events.Payload, threshold: f64) ?consolidate.Reason {
    const session = payload.session_id orelse return null;
    var usage_buf: [1024]u8 = undefined;
    const usage = if (env.usage_dir) |u| u[0..] else std.fmt.bufPrint(&usage_buf, "{s}/Library/Application Support/Cadex/usage", .{env.home}) catch return null;
    var paths: consolidate.Paths = .{};
    if (!paths.init(env.data_dir, usage, session)) return null;
    return consolidate.atStop(gpa, &paths, threshold, payload.stop_hook_active);
}

fn fetchReply(gpa: std.mem.Allocator, env: Env, payload: events.Payload, reply: Reply, milestone: consolidate.Reason, deadline: i64) !?[]u8 {
    const target = switch (reply) {
        .none => return null,
        .briefing => blk: {
            var handoff: std.ArrayList(u8) = .fromOwnedSlice(try events.handoffTarget(gpa, payload, env.workspace));
            errdefer handoff.deinit(gpa);
            try events.appendManaged(gpa, &handoff, env.run_id, null, false);
            break :blk try handoff.toOwnedSlice(gpa);
        },
        .anchor => try events.recapTarget(gpa, payload.session_id.?, context.anchor_budget),
        .recap => try events.recapTarget(gpa, payload.session_id.?, null),
        .brief => try events.briefTarget(gpa, payload, env.workspace),
        .consolidate_stop, .consolidate_asked => try consolidateTarget(gpa, payload, env.workspace, milestone),
    };
    defer gpa.free(target);
    const answer = (try http.send(gpa, env.socket, "GET", target, env.token, "", deadline)) orelse return null;
    defer answer.deinit(gpa);
    if (!answer.ok()) return null;
    const text = try briefingText(gpa, answer.body);
    defer gpa.free(text);
    if (text.len == 0) return null;
    return switch (reply) {
        .none => null,
        .briefing => try startOutput(gpa, text),
        .anchor => if (std.mem.startsWith(u8, text, context.anchor_header)) try startOutput(gpa, text) else null,
        .recap => try context.envelope(gpa, "UserPromptSubmit", text),
        .brief => try context.envelope(gpa, "SubagentStart", text),
        .consolidate_stop => try consolidate.blockOutput(gpa, text),
        .consolidate_asked => try context.envelope(gpa, "UserPromptSubmit", text),
    };
}

/// The request's query: the session, the milestone, and the folder and
/// workspace the engine names the project by (the hooks' own scope).
fn consolidateTarget(gpa: std.mem.Allocator, payload: events.Payload, workspace: ?[]const u8, reason: consolidate.Reason) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/cadex/consolidate?session_id=");
    try events.appendEncoded(gpa, &out, payload.session_id.?);
    try out.print(gpa, "&reason={s}", .{consolidate.name(reason)});
    if (payload.cwd) |cwd| {
        try out.appendSlice(gpa, "&cwd=");
        try events.appendEncoded(gpa, &out, cwd);
    }
    if (workspace) |w| {
        try out.appendSlice(gpa, "&workspace=");
        try events.appendEncoded(gpa, &out, w);
    }
    return out.toOwnedSlice(gpa);
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
    try testing.expect(env.bin == null and env.tokens_dir == null and env.workspace == null);
}

fn accountEnv(name: [*:0]const u8) ?[:0]const u8 {
    if (std.mem.eql(u8, std.mem.span(name), "CADEX_MEMORY_WORKSPACE")) return "-Users-u--claude-x";
    return testEnv(name);
}

test "an account's own memory is read from CADEX_MEMORY_WORKSPACE" {
    var socket_buf: [256]u8 = undefined;
    var dir_buf: [1024]u8 = undefined;
    try testing.expectEqualStrings("-Users-u--claude-x", Env.from(accountEnv, &socket_buf, &dir_buf).?.workspace.?);
}

test "what each event brings back" {
    try testing.expectEqual(Reply.briefing, replyFor("session-start", .{ .source = "resume" }));
    try testing.expectEqual(Reply.anchor, replyFor("session-start", .{ .source = "compact", .session_id = "s" }));
    try testing.expectEqual(Reply.none, replyFor("session-start", .{ .source = "compact", .session_id = "s", .agent_id = "a" }));
    try testing.expectEqual(Reply.recap, replyFor("user-prompt-submit", .{ .session_id = "s", .prompt = "Reload context, then go" }));
    try testing.expectEqual(Reply.none, replyFor("user-prompt-submit", .{ .session_id = "s", .prompt = "fix it" }));
    try testing.expectEqual(Reply.brief, replyFor("subagent-start", .{}));
    try testing.expectEqual(Reply.none, replyFor("stop", .{}));
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
