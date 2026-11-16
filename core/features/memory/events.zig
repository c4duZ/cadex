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
    /// SessionStart's `startup`, `resume`, `clear` or `compact`.
    source: ?[]const u8 = null,
    /// Set when the hook fired inside a subagent (Claude Code 2.1.323+).
    agent_id: ?[]const u8 = null,
    /// UserPromptSubmit's text.
    prompt: ?[]const u8 = null,
    /// Stop's flag: the session already goes on because of a Stop hook.
    stop_hook_active: bool = false,

    pub fn of(value: std.json.Value) Payload {
        if (value != .object) return .{};
        return .{
            .session_id = string(value, "session_id"),
            .cwd = string(value, "cwd"),
            .source = string(value, "source"),
            .agent_id = string(value, "agent_id"),
            .prompt = string(value, "prompt"),
            .stop_hook_active = if (value.object.get("stop_hook_active")) |v| v == .bool and v.bool else false,
        };
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

/// `/hook?event=…&agent=claude-code&cwd=…[&workspace=…]&session_id=…&project_strategy=repo-root&ingest_key=…[&pid=…]`.
/// `repo-root` from the first session on, so a worktree joins its
/// repository's memory instead of becoming a project of its own (plan 22).
/// `workspace`: the account's own memory (CADEX_MEMORY_WORKSPACE, set by the
/// kit when memory.shareAcrossAccounts is off); none is the engine's `default`.
pub fn hookTarget(gpa: std.mem.Allocator, engine_event: []const u8, payload: Payload, workspace: ?[]const u8, ingest_key: []const u8, pid: ?c_int) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/hook?");
    try appendPair(gpa, &out, "event", engine_event);
    try appendPair(gpa, &out, "agent", "claude-code");
    if (payload.cwd) |cwd| try appendPair(gpa, &out, "cwd", cwd);
    if (workspace) |name| try appendPair(gpa, &out, "workspace", name);
    if (payload.session_id) |id| try appendPair(gpa, &out, "session_id", id);
    try appendPair(gpa, &out, "project_strategy", "repo-root");
    try appendPair(gpa, &out, "ingest_key", ingest_key);
    if (pid) |p| try out.print(gpa, "&pid={d}", .{p});
    return out.toOwnedSlice(gpa);
}

/// `GET /handoff` with `briefing=1`: without it the project's pages stay
/// out of the briefing (plan 22). The same `workspace` as the hook's, so the
/// briefing comes from the memory the events went to.
pub fn handoffTarget(gpa: std.mem.Allocator, payload: Payload, workspace: ?[]const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/handoff?");
    try appendPair(gpa, &out, "agent", "claude-code");
    if (payload.cwd) |cwd| try appendPair(gpa, &out, "cwd", cwd);
    if (workspace) |name| try appendPair(gpa, &out, "workspace", name);
    try appendPair(gpa, &out, "project_strategy", "repo-root");
    try appendPair(gpa, &out, "briefing", "1");
    if (payload.session_id) |id| try appendPair(gpa, &out, "session_id", id);
    return out.toOwnedSlice(gpa);
}

/// `GET /recap` of the session: the window the last compaction dropped, or
/// with `anchor` the short post-compaction anchor (upstream's `recap_url`
/// and `anchor_url`).
pub fn recapTarget(gpa: std.mem.Allocator, session_id: []const u8, anchor_budget: ?u32) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/recap?");
    try appendPair(gpa, &out, "agent", "claude-code");
    try appendPair(gpa, &out, "session_id", session_id);
    if (anchor_budget) |budget| try out.print(gpa, "&budget={d}&mode=anchor", .{budget});
    return out.toOwnedSlice(gpa);
}

/// `GET /brief` for a subagent: the project's brief, read-only (it never
/// claims the parent's handoff). No `briefing=1`: the engine adds the
/// repository's `inject_on_subagent_start` when there is one, and gives
/// nothing otherwise, as upstream does.
pub fn briefTarget(gpa: std.mem.Allocator, payload: Payload, workspace: ?[]const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.appendSlice(gpa, "/brief?");
    try appendPair(gpa, &out, "agent", "claude-code");
    if (payload.cwd) |cwd| try appendPair(gpa, &out, "cwd", cwd);
    if (workspace) |name| try appendPair(gpa, &out, "workspace", name);
    try appendPair(gpa, &out, "project_strategy", "repo-root");
    return out.toOwnedSlice(gpa);
}

/// Whether `value` is a UUID in its text form (8-4-4-4-12 hex), the shape of
/// upstream's `ManagedRunId`.
pub fn isUuid(value: []const u8) bool {
    if (value.len != 36) return false;
    for (value, 0..) |c, i| {
        const dash = i == 8 or i == 13 or i == 18 or i == 23;
        if (dash != (c == '-')) return false;
        if (!dash and !std.ascii.isHex(c)) return false;
    }
    return true;
}

/// What a managed run (`cadex-memory run`, plan 22 phase E) adds to the
/// hook's and the handoff's query, as upstream's hook client does from the
/// same variables (`managed_run_query_suffix` and `auto_handoff_query_suffix`
/// in its hook.rs at fa0ec25): `&managed_run=<AI_MEMORY_RUN_ID>` when that is
/// a run id, so the startup packet is the workstream's; `&auto_handoff=0`
/// (hook only) when AI_MEMORY_AUTO_HANDOFF is falsy.
pub fn appendManaged(gpa: std.mem.Allocator, target: *std.ArrayList(u8), run_id: ?[]const u8, auto_handoff: ?[]const u8, on_hook: bool) !void {
    if (run_id) |id| if (isUuid(id)) try target.print(gpa, "&managed_run={s}", .{id});
    if (!on_hook) return;
    const off = auto_handoff orelse return;
    const v = std.mem.trim(u8, off, " \t");
    for ([_][]const u8{ "0", "false", "no", "off" }) |f| {
        if (std.ascii.eqlIgnoreCase(v, f)) return target.appendSlice(gpa, "&auto_handoff=0");
    }
}

const testing = std.testing;

test "a managed run's id and the handoff switch go on the query" {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(testing.allocator);
    try appendManaged(testing.allocator, &out, "0198c3a0-1b2c-7d3e-8f40-123456789abc", "False", true);
    try testing.expectEqualStrings("&managed_run=0198c3a0-1b2c-7d3e-8f40-123456789abc&auto_handoff=0", out.items);
    out.clearRetainingCapacity();
    try appendManaged(testing.allocator, &out, "not-a-run", "1", true);
    try testing.expectEqualStrings("", out.items);
    try appendManaged(testing.allocator, &out, "0198c3a0-1b2c-7d3e-8f40-123456789abc", "off", false);
    try testing.expectEqualStrings("&managed_run=0198c3a0-1b2c-7d3e-8f40-123456789abc", out.items);
}

test "recap and brief queries" {
    const recap = try recapTarget(testing.allocator, "s 1", null);
    defer testing.allocator.free(recap);
    try testing.expectEqualStrings("/recap?agent=claude-code&session_id=s%201", recap);
    const anchor = try recapTarget(testing.allocator, "s", 2000);
    defer testing.allocator.free(anchor);
    try testing.expectEqualStrings("/recap?agent=claude-code&session_id=s&budget=2000&mode=anchor", anchor);
    const brief = try briefTarget(testing.allocator, .{ .cwd = "/p", .session_id = "s" }, "w");
    defer testing.allocator.free(brief);
    try testing.expectEqualStrings("/brief?agent=claude-code&cwd=%2Fp&workspace=w&project_strategy=repo-root", brief);
}

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
    const target = try hookTarget(testing.allocator, "session-start", payload, null, "k1", 42);
    defer testing.allocator.free(target);
    try testing.expectEqualStrings("/hook?event=session-start&agent=claude-code&cwd=%2FUsers%2Fa%20b%2Fa%C3%A7%C3%A3o%26x" ++
        "&session_id=s-1&project_strategy=repo-root&ingest_key=k1&pid=42", target);
    const bare = try hookTarget(testing.allocator, "stop", .{}, null, "k2", null);
    defer testing.allocator.free(bare);
    try testing.expectEqualStrings("/hook?event=stop&agent=claude-code&project_strategy=repo-root&ingest_key=k2", bare);
    const handoff = try handoffTarget(testing.allocator, payload, null);
    defer testing.allocator.free(handoff);
    try testing.expect(std.mem.startsWith(u8, handoff, "/handoff?agent=claude-code&cwd=%2FUsers"));
    try testing.expect(std.mem.endsWith(u8, handoff, "&project_strategy=repo-root&briefing=1&session_id=s-1"));
}

test "an account's own memory: the workspace goes on the hook and on the handoff" {
    const payload: Payload = .{ .session_id = "s", .cwd = "/p" };
    const target = try hookTarget(testing.allocator, "stop", payload, "-Users-a--claude-x", "k", null);
    defer testing.allocator.free(target);
    try testing.expectEqualStrings("/hook?event=stop&agent=claude-code&cwd=%2Fp&workspace=-Users-a--claude-x" ++
        "&session_id=s&project_strategy=repo-root&ingest_key=k", target);
    const handoff = try handoffTarget(testing.allocator, payload, "-Users-a--claude-x");
    defer testing.allocator.free(handoff);
    try testing.expectEqualStrings("/handoff?agent=claude-code&cwd=%2Fp&workspace=-Users-a--claude-x" ++
        "&project_strategy=repo-root&briefing=1&session_id=s", handoff);
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
