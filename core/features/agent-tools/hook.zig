//! `cadex hook <event>`: the hook command the session kit puts in the
//! `--settings` of the sessions Cadex opens (docs/adr/0022-terminal-daemon.md).
//! It reads the hook's JSON from stdin and sends one line to the app's
//! socket: the session's token (CADEX_SESSION_TOKEN, from the kit's settings
//! `env`, which reaches hooks: tested 2026-11-15), the event, the pid of the
//! `claude` that ran it (the hook's parent) and the JSON. It never makes the
//! session wait: 200 ms for an answer, and with the app closed it returns at
//! once. The one exception is PermissionRequest, which waits for the owner's
//! click (docs/adr/0023-answer-agent-permissions.md). Exit code 0 always.

const std = @import("std");
const edits = @import("edits.zig");
extern "c" fn getppid() c_int;
extern "c" fn time(t: ?*c_long) c_long;

/// How long an event waits for the app; a permission waits for a click.
pub fn waitMs(event: []const u8) u32 {
    return if (std.mem.eql(u8, event, "PermissionRequest")) 10 * 60 * 1000 else 200;
}

/// The line sent to the app: the payload written again on one line (the
/// hook's JSON may come over several lines, or end with one, which broke the
/// line in two: found 2026-11-15), or null when it is not JSON.
pub fn message(gpa: std.mem.Allocator, token: []const u8, event: []const u8, pid: c_int, payload: []const u8) ![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, payload, .{}) catch null;
    defer if (parsed) |*p| p.deinit();
    const value: std.json.Value = if (parsed) |p| p.value else .null;
    // An edit's payload carries the whole file: only its ranges go (ADR 0027).
    if (std.mem.eql(u8, event, "PostToolUse")) {
        const cut = try edits.trimmed(gpa, value);
        defer gpa.free(cut);
        return std.fmt.allocPrint(gpa, "{{\"v\":1,\"token\":{f},\"event\":{f},\"pid\":{d},\"payload\":{s}}}\n", .{
            std.json.fmt(token, .{}), std.json.fmt(event, .{}), pid, cut,
        });
    }
    return std.fmt.allocPrint(gpa, "{{\"v\":1,\"token\":{f},\"event\":{f},\"pid\":{d},\"payload\":{f}}}\n", .{
        std.json.fmt(token, .{}), std.json.fmt(event, .{}), pid, std.json.fmt(value, .{}),
    });
}

/// What the hook prints from the app's answer: its "stdout" (a decision for
/// Claude Code), or nothing.
pub fn printed(gpa: std.mem.Allocator, answer: []const u8) !?[]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, answer, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const out = parsed.value.object.get("stdout") orelse return null;
    if (out != .string or out.string.len == 0) return null;
    return try gpa.dupe(u8, out.string);
}

/// The socket: CADEX_APP_SOCKET (tests), else Cadex's folder.
pub fn socketPath(out: []u8) ?[]const u8 {
    if (std.c.getenv("CADEX_APP_SOCKET")) |value| {
        const path = std.mem.span(value);
        if (path.len > 0 and path.len <= out.len) {
            @memcpy(out[0..path.len], path);
            return out[0..path.len];
        }
    }
    const home = std.mem.span(std.c.getenv("HOME") orelse return null);
    return std.fmt.bufPrint(out, "{s}/Library/Application Support/Cadex/sockets/app.sock", .{home}) catch null;
}

/// Whether the app's socket takes a connection (the app is there, maybe busy).
pub fn reachable(path: []const u8) bool {
    const c = std.c;
    var address: c.sockaddr.un = .{ .family = c.AF.UNIX, .path = undefined };
    if (path.len >= address.path.len) return false;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const fd = c.socket(c.AF.UNIX, c.SOCK.STREAM, 0);
    if (fd < 0) return false;
    defer _ = c.close(fd);
    return c.connect(fd, @ptrCast(&address), @sizeOf(c.sockaddr.un)) == 0;
}

/// One exchange: send `line`, read one line back within `wait_ms`. null
/// when the app is not there or did not answer in time.
pub fn exchange(gpa: std.mem.Allocator, path: []const u8, line: []const u8, wait_ms: u32) !?[]u8 {
    const c = std.c;
    var address: c.sockaddr.un = .{ .family = c.AF.UNIX, .path = undefined };
    if (path.len >= address.path.len) return null;
    @memset(&address.path, 0);
    @memcpy(address.path[0..path.len], path);
    const fd = c.socket(c.AF.UNIX, c.SOCK.STREAM, 0);
    if (fd < 0) return null;
    defer _ = c.close(fd);
    const timeout: c.timeval = .{ .sec = @intCast(wait_ms / 1000), .usec = @intCast((wait_ms % 1000) * 1000) };
    _ = c.setsockopt(fd, c.SOL.SOCKET, c.SO.RCVTIMEO, std.mem.asBytes(&timeout), @sizeOf(c.timeval));
    _ = c.setsockopt(fd, c.SOL.SOCKET, c.SO.SNDTIMEO, std.mem.asBytes(&timeout), @sizeOf(c.timeval));
    if (c.connect(fd, @ptrCast(&address), @sizeOf(c.sockaddr.un)) != 0) return null;
    var sent: usize = 0;
    while (sent < line.len) {
        const n = c.write(fd, line[sent..].ptr, line.len - sent);
        if (n <= 0) return null;
        sent += @intCast(n);
    }
    var answer: std.ArrayList(u8) = .empty;
    errdefer answer.deinit(gpa);
    var buf: [4096]u8 = undefined;
    while (std.mem.indexOfScalar(u8, answer.items, '\n') == null and answer.items.len < 1024 * 1024) {
        const n = c.read(fd, &buf, buf.len);
        if (n <= 0) break;
        try answer.appendSlice(gpa, buf[0..@intCast(n)]);
    }
    if (answer.items.len == 0) {
        answer.deinit(gpa);
        return null;
    }
    return try answer.toOwnedSlice(gpa);
}

/// The whole command: the stdin JSON in, what to print out (maybe nothing).
pub fn run(gpa: std.mem.Allocator, event: []const u8, input: []const u8) !?[]u8 {
    const token = std.mem.span(std.c.getenv("CADEX_SESSION_TOKEN") orelse return null);
    if (token.len == 0) return null;
    var path_buf: [256]u8 = undefined;
    const path = socketPath(&path_buf) orelse return null;
    const line = try message(gpa, token, event, getppid(), input);
    defer gpa.free(line);
    const answer = (try exchange(gpa, path, line, waitMs(event))) orelse return null;
    defer gpa.free(answer);
    return printed(gpa, std.mem.trimEnd(u8, answer, "\n"));
}

const testing = std.testing;

test "a payload over several lines, or ending with one, still makes one line" {
    const line = try message(testing.allocator, "t", "Stop", 1, "{\n  \"a\": \"x\\ny\"\n}\n");
    defer testing.allocator.free(line);
    try testing.expectEqualStrings("{\"v\":1,\"token\":\"t\",\"event\":\"Stop\",\"pid\":1,\"payload\":{\"a\":\"x\\ny\"}}\n", line);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, line, "\n"));
}

test "the line carries the token, event, pid and the JSON as it came" {
    const line = try message(testing.allocator, "tok", "Stop", 42, "{\"session_id\":\"s1\"}");
    defer testing.allocator.free(line);
    try testing.expectEqualStrings("{\"v\":1,\"token\":\"tok\",\"event\":\"Stop\",\"pid\":42,\"payload\":{\"session_id\":\"s1\"}}\n", line);
    const bad = try message(testing.allocator, "t\"x", "Stop", 1, "not json");
    defer testing.allocator.free(bad);
    try testing.expect(std.mem.indexOf(u8, bad, "\"payload\":null") != null and std.mem.indexOf(u8, bad, "t\\\"x") != null);
}

test "only a permission waits; the answer's stdout is printed" {
    try testing.expectEqual(@as(u32, 200), waitMs("Stop"));
    try testing.expect(waitMs("PermissionRequest") > 60_000);
    const out = (try printed(testing.allocator, "{\"ok\":true,\"stdout\":\"{\\\"decision\\\":1}\"}")).?;
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"decision\":1}", out);
    try testing.expect((try printed(testing.allocator, "{\"ok\":true}")) == null);
}

test "with no app on the socket the exchange gives up at once" {
    const start = time(null);
    const got = try exchange(testing.allocator, "/nonexistent/cadex/app.sock", "x\n", 200);
    try testing.expect(got == null);
    try testing.expect(time(null) - start <= 1);
}

test "PostToolUse goes as ranges, never with the file" {
    const line = try message(testing.allocator, "t", "PostToolUse", 7,
        "{\"session_id\":\"s\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/a\"},\"tool_response\":{\"originalFile\":\"WHOLE\",\"structuredPatch\":[{\"newStart\":3,\"lines\":[\"+x\"]}]}}");
    defer testing.allocator.free(line);
    try testing.expect(std.mem.indexOf(u8, line, "WHOLE") == null);
    try testing.expect(std.mem.indexOf(u8, line, "\"lines\":[[3,3]]") != null);
}
