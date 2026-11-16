//! The memory's tools in `cadex mcp` (plan 22 phase D): the engine's own
//! MCP tools, listed by the engine and called through it, as upstream's
//! session-aware `mcp-bridge` does (crates/ai-memory-cli/src/commands/
//! mcp_bridge.rs at fa0ec25): every request carries Claude Code's session id
//! (`CLAUDE_CODE_SESSION_ID`, which Claude Code gives its MCP servers) as
//! `X-Memory-Actor-Session-Id`, so a call that names no project lands on
//! the session's. `X-Cadex-Cwd` and `X-Cadex-Workspace` give the engine the
//! folder `cadex mcp` started in and the account's workspace, from which it
//! fills upstream's fallback scope headers (server/src/mcp_scope.rs) for a
//! call made before the session's first hook.
//!
//! Left out: the tools for an administrator or an LLM provider, which Cadex
//! has neither of (ADR 0028).

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const hook = @import("hook_client.zig");
const http = @import("http.zig");
const launch = @import("launch.zig");
const events = @import("events.zig");

/// The tools `cadex mcp` does not offer: an administrator's (sweep, restore),
/// an LLM provider's (consolidate, auto-improve) and the installer's.
pub const excluded = [_][]const u8{
    "memory_auto_improve",
    "memory_consolidate",
    "memory_forget_sweep",
    "memory_install_self_routing",
    "memory_restore_page",
};

/// The list waits for the engine to start (the session's SessionStart may
/// still be starting it); a call may load the embedding model (~400 ms) or
/// write many pages.
pub const list_budget_ms = 3000;
pub const call_budget_ms = 30_000;

pub fn offers(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, "memory_")) return false;
    for (excluded) |x| if (std.mem.eql(u8, x, name)) return false;
    return true;
}

pub const Proxy = struct {
    env: hook.Env,
    session_id: ?[]const u8,
    cwd: ?[]const u8,
    cwd_buf: [1024]u8 = undefined,
    socket_buf: [256]u8 = undefined,
    dir_buf: [1024]u8 = undefined,

    /// From the process: null when the memory is off for this session (the
    /// kit gives no CADEX_MEMORY_DIR) or the session is not Cadex's.
    pub fn init(self: *Proxy) bool {
        if (hook.Env.processEnv("CADEX_MEMORY_DIR") == null) return false;
        self.env = hook.Env.from(hook.Env.processEnv, &self.socket_buf, &self.dir_buf) orelse return false;
        self.session_id = hook.Env.processEnv("CLAUDE_CODE_SESSION_ID");
        self.cwd = if (std.c.getcwd(&self.cwd_buf, self.cwd_buf.len)) |p| std.mem.span(@as([*:0]u8, @ptrCast(p))) else null;
        return true;
    }

    /// One JSON-RPC message to the engine's `/mcp`; the engine is started
    /// when it is down.
    fn exchange(self: *const Proxy, gpa: std.mem.Allocator, body: []const u8, budget_ms: i64) !?http.Response {
        const deadline = clock.monotonicMs() + budget_ms;
        if (self.env.bin) |bin| {
            _ = launch.ensure(.{ .bin = bin, .socket = self.env.socket, .data_dir = self.env.data_dir, .tokens_dir = self.env.tokens_dir }, deadline);
        }
        var arena: std.heap.ArenaAllocator = .init(gpa);
        defer arena.deinit();
        var headers: std.ArrayList(http.Header) = .empty;
        if (self.session_id) |id| if (headerSafe(id)) try headers.append(arena.allocator(), .{ .name = "X-Memory-Actor-Session-Id", .value = id });
        if (self.cwd) |cwd| {
            var encoded: std.ArrayList(u8) = .empty;
            try events.appendEncoded(arena.allocator(), &encoded, cwd);
            try headers.append(arena.allocator(), .{ .name = "X-Cadex-Cwd", .value = encoded.items });
        }
        if (self.env.workspace) |w| if (headerSafe(w)) try headers.append(arena.allocator(), .{ .name = "X-Cadex-Workspace", .value = w });
        return http.sendWith(gpa, self.env.socket, "POST", "/mcp", self.env.token, headers.items, body, deadline);
    }

    /// The engine's tools `cadex mcp` offers, as JSON objects joined by
    /// commas (to append to its own list); null when the engine does not
    /// answer.
    pub fn listTools(self: *const Proxy, gpa: std.mem.Allocator) !?[]u8 {
        const answer = (try self.exchange(gpa, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}", list_budget_ms)) orelse return null;
        defer answer.deinit(gpa);
        if (!answer.ok()) return null;
        return try filterTools(gpa, answer.body);
    }

    /// A `tools/call` message as the client sent it; the engine's answer as
    /// is (same id). Null when the engine does not answer.
    pub fn call(self: *const Proxy, gpa: std.mem.Allocator, message: []const u8) !?[]u8 {
        const answer = (try self.exchange(gpa, message, call_budget_ms)) orelse return null;
        defer answer.deinit(gpa);
        if (!answer.ok()) return null;
        const body = std.mem.trimEnd(u8, answer.body, " \r\n");
        return try std.fmt.allocPrint(gpa, "{s}\n", .{body});
    }
};

fn headerSafe(value: []const u8) bool {
    for (value) |b| if (b < 0x20 or b >= 0x7f) return false;
    return value.len > 0;
}

/// The offered tools of a `tools/list` answer, re-serialized.
pub fn filterTools(gpa: std.mem.Allocator, body: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, body, .{}) catch return null;
    defer parsed.deinit();
    const result = if (parsed.value == .object) parsed.value.object.get("result") else null;
    const list = if (result) |r| (if (r == .object) r.object.get("tools") else null) else null;
    if (list == null or list.? != .array) return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    for (list.?.array.items) |tool| {
        if (tool != .object) continue;
        const name = tool.object.get("name") orelse continue;
        if (name != .string or !offers(name.string)) continue;
        if (out.items.len > 0) try out.append(gpa, ',');
        try out.print(gpa, "{f}", .{std.json.fmt(tool, .{})});
    }
    return try out.toOwnedSlice(gpa);
}

const testing = std.testing;

test "the memory's tools, without the administrator's and the provider's" {
    try testing.expect(offers("memory_query") and offers("memory_write_page"));
    try testing.expect(!offers("memory_consolidate") and !offers("memory_restore_page") and !offers("cadex_open"));
    const body =
        \\{"jsonrpc":"2.0","id":1,"result":{"tools":[
        \\{"name":"memory_query","description":"Search","inputSchema":{"type":"object"}},
        \\{"name":"memory_forget_sweep","description":"Sweep","inputSchema":{"type":"object"}},
        \\{"name":"memory_status","description":"Counts","inputSchema":{"type":"object"}}]}}
    ;
    const tools = (try filterTools(testing.allocator, body)).?;
    defer testing.allocator.free(tools);
    try testing.expect(std.mem.indexOf(u8, tools, "\"memory_query\"") != null);
    try testing.expect(std.mem.indexOf(u8, tools, "\"memory_status\"") != null);
    try testing.expect(std.mem.indexOf(u8, tools, "sweep") == null);
    try testing.expect(try filterTools(testing.allocator, "not json") == null);
}
