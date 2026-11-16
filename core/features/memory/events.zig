//! What a Claude Code hook becomes on the engine's wire: the event name
//! ai-memory's hook router takes (`HookEvent::parse` in its ai-memory-hooks
//! crate, payload.rs; the same names its Claude Code plugin's hooks.json
//! sends) and the query of `POST /hook` and `GET /handoff`.

const std = @import("std");

extern "c" fn arc4random_buf(buf: *anyopaque, nbytes: usize) void;

/// Claude Code's hook event -> ai-memory's. null: not one the memory takes.
pub fn engineEvent(claude_event: []const u8) ?[]const u8 {
    const table = [_]struct { []const u8, []const u8 }{
        .{ "SessionStart", "session-start" },
        .{ "UserPromptSubmit", "user-prompt-submit" },
        .{ "PreToolUse", "pre-tool-use" },
        .{ "PostToolUse", "post-tool-use" },
        .{ "PostToolUseFailure", "post-tool-use" },
        .{ "PreCompact", "pre-compact" },
        // Claude Code says PostCompact; the engine's name is Devin's.
        .{ "PostCompact", "post-compaction" },
        .{ "Notification", "notification" },
        .{ "Stop", "stop" },
        .{ "SessionEnd", "session-end" },
        .{ "SubagentStart", "subagent-start" },
        .{ "SubagentStop", "subagent-stop" },
    };
    for (table) |row| if (std.mem.eql(u8, row[0], claude_event)) return row[1];
    return null;
}

/// The events whose `claude` pid the engine tracks: it leaves when the last
/// one ends (core/features/memory/server/src/sessions.rs).
pub fn sendsPid(engine_event: []const u8) bool {
    return std.mem.eql(u8, engine_event, "session-start") or std.mem.eql(u8, engine_event, "session-end");
}

/// Percent-encodes everything but RFC 3986's unreserved characters.
pub fn appendEncoded(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try out.append(gpa, byte);
        } else {
            try out.print(gpa, "%{X:0>2}", .{byte});
        }
    }
}

fn appendPair(gpa: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: []const u8) !void {
    if (out.items.len > 0 and out.items[out.items.len - 1] != '?') try out.append(gpa, '&');
    try out.appendSlice(gpa, key);
    try out.append(gpa, '=');
    try appendEncoded(gpa, out, value);
}

/// The fields of the hook's JSON the query repeats. Slices into the parse.
pub const Payload = struct {
    session_id: ?[]const u8 = null,
    cwd: ?[]const u8 = null,

    pub fn of(value: std.json.Value) Payload {
        if (value != .object) return .{};
        return .{ .session_id = string(value, "session_id"), .cwd = string(value, "cwd") };
    }

    fn string(value: std.json.Value, key: []const u8) ?[]const u8 {
        const v = value.object.get(key) orelse return null;
        return if (v == .string and v.string.len > 0) v.string else null;
    }
};

/// A random ingest key, 32 hex characters: the engine drops a second copy
/// of the same event (a spooled one sent again) by this key.
pub fn ingestKey(out: *[32]u8) []const u8 {
    var bytes: [16]u8 = undefined;
    arc4random_buf(&bytes, bytes.len);
    const hex = std.fmt.bytesToHex(bytes, .lower);
    out.* = hex;
    return out;
}

/// `/hook?event=…&agent=claude-code&cwd=…&session_id=…&project_strategy=repo-root&ingest_key=…[&pid=…]`.
/// `repo-root` from the first session on, so a worktree joins its
/// repository's memory instead of becoming a project of its own (plan 22).
pub fn hookTarget(gpa: std.mem.Allocator, engine_event: []const u8, payload: Payload, ingest_key: []const u8, pid: ?c_int) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/hook?");
    try appendPair(gpa, &out, "event", engine_event);
    try appendPair(gpa, &out, "agent", "claude-code");
    if (payload.cwd) |cwd| try appendPair(gpa, &out, "cwd", cwd);
    if (payload.session_id) |id| try appendPair(gpa, &out, "session_id", id);
    try appendPair(gpa, &out, "project_strategy", "repo-root");
    try appendPair(gpa, &out, "ingest_key", ingest_key);
    if (pid) |p| try out.print(gpa, "&pid={d}", .{p});
    return out.toOwnedSlice(gpa);
}

/// `GET /handoff` with `briefing=1`: without it the project's pages stay
/// out of the briefing (plan 22).
pub fn handoffTarget(gpa: std.mem.Allocator, payload: Payload) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/handoff?");
    try appendPair(gpa, &out, "agent", "claude-code");
    if (payload.cwd) |cwd| try appendPair(gpa, &out, "cwd", cwd);
    try appendPair(gpa, &out, "project_strategy", "repo-root");
    try appendPair(gpa, &out, "briefing", "1");
    if (payload.session_id) |id| try appendPair(gpa, &out, "session_id", id);
    return out.toOwnedSlice(gpa);
}

const testing = std.testing;

test "Claude Code's events map to the engine's names" {
    try testing.expectEqualStrings("session-start", engineEvent("SessionStart").?);
    try testing.expectEqualStrings("user-prompt-submit", engineEvent("UserPromptSubmit").?);
    try testing.expectEqualStrings("post-tool-use", engineEvent("PostToolUseFailure").?);
    try testing.expectEqualStrings("post-compaction", engineEvent("PostCompact").?);
    try testing.expectEqualStrings("subagent-stop", engineEvent("SubagentStop").?);
    try testing.expect(engineEvent("PermissionRequest") == null);
    try testing.expect(engineEvent("session-start") == null);
    try testing.expect(sendsPid("session-end") and !sendsPid("stop"));
}

test "the hook's query encodes the folder and carries the pid only when asked" {
    const payload: Payload = .{ .session_id = "s-1", .cwd = "/Users/a b/ação&x" };
    const target = try hookTarget(testing.allocator, "session-start", payload, "k1", 42);
    defer testing.allocator.free(target);
    try testing.expectEqualStrings("/hook?event=session-start&agent=claude-code&cwd=%2FUsers%2Fa%20b%2Fa%C3%A7%C3%A3o%26x" ++
        "&session_id=s-1&project_strategy=repo-root&ingest_key=k1&pid=42", target);
    const bare = try hookTarget(testing.allocator, "stop", .{}, "k2", null);
    defer testing.allocator.free(bare);
    try testing.expectEqualStrings("/hook?event=stop&agent=claude-code&project_strategy=repo-root&ingest_key=k2", bare);
    const handoff = try handoffTarget(testing.allocator, payload);
    defer testing.allocator.free(handoff);
    try testing.expect(std.mem.startsWith(u8, handoff, "/handoff?agent=claude-code&cwd=%2FUsers"));
    try testing.expect(std.mem.endsWith(u8, handoff, "&project_strategy=repo-root&briefing=1&session_id=s-1"));
}

test "the payload's session and folder are read; ingest keys differ" {
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, "{\"session_id\":\"abc\",\"cwd\":\"/p\",\"x\":1}", .{});
    defer parsed.deinit();
    const payload = Payload.of(parsed.value);
    try testing.expectEqualStrings("abc", payload.session_id.?);
    try testing.expectEqualStrings("/p", payload.cwd.?);
    try testing.expect(Payload.of(.null).cwd == null);
    var a: [32]u8 = undefined;
    var b: [32]u8 = undefined;
    try testing.expect(!std.mem.eql(u8, ingestKey(&a), ingestKey(&b)));
}
