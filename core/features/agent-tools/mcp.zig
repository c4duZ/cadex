//! `cadex mcp`: an MCP server over stdin and stdout, one JSON-RPC message
//! per line (docs/adr/0024-agent-tools.md). The session kit registers it in
//! the sessions Cadex opens; it inherits the session's environment, token
//! included (tested 2026-11-15). Each tool is a command request to the app
//! (request.zig); nothing of the app lives here. Plan 20 phase C adds the
//! browser's tools, phase E the computer's.

const std = @import("std");
const request = @import("request.zig");

pub const Send = *const fn (gpa: std.mem.Allocator, id: []const u8, args: []const request.Arg) anyerror!request.Reply;

const Tool = struct {
    name: []const u8,
    command: []const u8,
    description: []const u8,
    /// The JSON Schema of the arguments, written out.
    schema: []const u8,
};

pub const tools = [_]Tool{
    .{ .name = "cadex_open", .command = "agent-tools.open-file", .description = "Open a file in Cadex, beside this terminal, optionally at a line.",
        .schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"},\"line\":{\"type\":\"integer\"}},\"required\":[\"path\"]}" },
    .{ .name = "cadex_diff", .command = "agent-tools.open-diff", .description = "Open the git diff of a file, or of the whole task, beside this terminal.",
        .schema = "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\"}}}" },
    .{ .name = "cadex_preview", .command = "preview.open", .description = "Open a web page (a dev server, docs) in Cadex's preview, beside this terminal.",
        .schema = "{\"type\":\"object\",\"properties\":{\"url\":{\"type\":\"string\"}},\"required\":[\"url\"]}" },
    .{ .name = "cadex_notify", .command = "agent-tools.notify", .description = "Notify the owner (macOS notification and a line in Cadex's feed): something long finished, a decision is needed, or you are blocked. One short sentence.",
        .schema = "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"}},\"required\":[\"text\"]}" },
    .{ .name = "cadex_worktree_status", .command = "worktrees.set-status", .description = "Set this task's status in Cadex: doing when you start, review when it is ready for the owner.",
        .schema = "{\"type\":\"object\",\"properties\":{\"status\":{\"type\":\"string\",\"enum\":[\"todo\",\"doing\",\"review\",\"done\"]}},\"required\":[\"status\"]}" },
    .{ .name = "cadex_worktree_comment", .command = "worktrees.set-comment", .description = "Say in a few words what this task is doing now (shown in Cadex's Tasks).",
        .schema = "{\"type\":\"object\",\"properties\":{\"comment\":{\"type\":\"string\"}},\"required\":[\"comment\"]}" },
};

const instructions = "Cadex holds this terminal. Use these tools to open files, diffs and pages beside it, to notify the owner and to mark the task's progress. More: run `cadex skills get cadex`.";

/// The answer to one message, or null when none is due (a notification).
pub fn handle(gpa: std.mem.Allocator, message: []const u8, send: Send) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, message, .{}) catch
        return try std.fmt.allocPrint(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{{\"code\":-32700,\"message\":\"parse error\"}}}}\n", .{});
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const object = parsed.value.object;
    const id = object.get("id") orelse return null;
    const method = if (object.get("method")) |m| (if (m == .string) m.string else "") else "";
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    try out.print(gpa, "{{\"jsonrpc\":\"2.0\",\"id\":{f},", .{std.json.fmt(id, .{})});
    if (std.mem.eql(u8, method, "initialize")) {
        const params = object.get("params");
        const asked = if (params) |p| (if (p == .object) p.object.get("protocolVersion") else null) else null;
        const version = if (asked) |v| (if (v == .string) v.string else "2025-06-18") else "2025-06-18";
        try out.print(gpa, "\"result\":{{\"protocolVersion\":{f},\"capabilities\":{{\"tools\":{{}}}},\"serverInfo\":{{\"name\":\"cadex\",\"version\":\"1\"}},\"instructions\":{f}}}}}\n", .{
            std.json.fmt(version, .{}), std.json.fmt(instructions, .{}),
        });
    } else if (std.mem.eql(u8, method, "tools/list")) {
        try out.appendSlice(gpa, "\"result\":{\"tools\":[");
        for (tools, 0..) |t, i| {
            if (i > 0) try out.append(gpa, ',');
            try out.print(gpa, "{{\"name\":\"{s}\",\"description\":{f},\"inputSchema\":{s}}}", .{ t.name, std.json.fmt(t.description, .{}), t.schema });
        }
        try out.appendSlice(gpa, "]}}\n");
    } else if (std.mem.eql(u8, method, "tools/call")) {
        try call(gpa, &out, object.get("params"), send);
    } else if (std.mem.eql(u8, method, "ping")) {
        try out.appendSlice(gpa, "\"result\":{}}\n");
    } else {
        try out.print(gpa, "\"error\":{{\"code\":-32601,\"message\":{f}}}}}\n", .{std.json.fmt(method, .{})});
    }
    return try out.toOwnedSlice(gpa);
}

/// A tool's call: its arguments as strings, the app's answer as text.
fn call(gpa: std.mem.Allocator, out: *std.ArrayList(u8), params: ?std.json.Value, send: Send) !void {
    const p = if (params) |v| (if (v == .object) v.object else null) else null;
    const name = if (p) |o| (if (o.get("name")) |n| (if (n == .string) n.string else "") else "") else "";
    const tool = for (tools) |t| (if (std.mem.eql(u8, t.name, name)) break t) else
        return result(gpa, out, false, "unknown tool");
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    var args: std.ArrayList(request.Arg) = .empty;
    if (p) |o| if (o.get("arguments")) |a| if (a == .object) {
        var it = a.object.iterator();
        while (it.next()) |entry| {
            const value = switch (entry.value_ptr.*) {
                .string => |s| s,
                .integer => |n| try std.fmt.allocPrint(arena.allocator(), "{d}", .{n}),
                .bool => |b| if (b) "true" else "false",
                else => continue,
            };
            try args.append(arena.allocator(), .{ .key = entry.key_ptr.*, .value = value });
        }
    };
    const reply = send(gpa, tool.command, args.items) catch |err| return result(gpa, out, false, switch (err) {
        error.NoToken => "not a session opened by Cadex",
        error.NotRunning => "Cadex is not running",
        else => "the request failed",
    });
    defer reply.deinit(gpa);
    try result(gpa, out, reply.ok, if (reply.text.len > 0) reply.text else if (reply.ok) "done" else "refused");
}

fn result(gpa: std.mem.Allocator, out: *std.ArrayList(u8), ok: bool, text: []const u8) !void {
    try out.print(gpa, "\"result\":{{\"content\":[{{\"type\":\"text\",\"text\":{f}}}],\"isError\":{}}}}}\n", .{ std.json.fmt(text, .{}), !ok });
}

const testing = std.testing;

fn fakeSend(gpa: std.mem.Allocator, id: []const u8, args: []const request.Arg) anyerror!request.Reply {
    const text = try std.fmt.allocPrint(gpa, "{s} {s}={s}", .{ id, args[0].key, args[0].value });
    return .{ .ok = true, .text = text, .raw = try gpa.dupe(u8, "") };
}

test "initialize, the list of tools and a call that reaches the app as a command" {
    const gpa = testing.allocator;
    const init = (try handle(gpa, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}", fakeSend)).?;
    defer gpa.free(init);
    try testing.expect(std.mem.indexOf(u8, init, "\"protocolVersion\":\"2025-06-18\"") != null);
    try testing.expect((try handle(gpa, "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}", fakeSend)) == null);
    const list = (try handle(gpa, "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"tools/list\"}", fakeSend)).?;
    defer gpa.free(list);
    try testing.expect(std.mem.indexOf(u8, list, "\"cadex_notify\"") != null and std.mem.indexOf(u8, list, "\"id\":\"a\"") != null);
    const called = (try handle(gpa, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"cadex_open\",\"arguments\":{\"path\":\"a.ts\"}}}", fakeSend)).?;
    defer gpa.free(called);
    try testing.expect(std.mem.indexOf(u8, called, "agent-tools.open-file path=a.ts") != null and std.mem.indexOf(u8, called, "\"isError\":false") != null);
    const unknown = (try handle(gpa, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"rm\"}}", fakeSend)).?;
    defer gpa.free(unknown);
    try testing.expect(std.mem.indexOf(u8, unknown, "\"isError\":true") != null);
    const odd = (try handle(gpa, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"resources/list\"}", fakeSend)).?;
    defer gpa.free(odd);
    try testing.expect(std.mem.indexOf(u8, odd, "-32601") != null);
}
