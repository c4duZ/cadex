//! Consolidation in the session, without a token (plan 22 phase F): at a
//! milestone the session's own Claude is asked to consolidate the session
//! into the memory with the memory tools; the request text is the engine's
//! (`GET /cadex/consolidate`, upstream's consolidation rules).
//!
//! Milestones, each once per session (a mark per session under
//! `<memory>/consolidate/`):
//! - the context fills past CADEX_MEMORY_CONSOLIDATE_AT percent, read from
//!   the session file `cadex statusline` writes (`<usage>/sessions/<id>.json`);
//! - the owner marks the task ready: the app leaves
//!   `<memory>/consolidate/requests/<session id>.ready`.
//! Both answer the Stop hook with `decision: "block"` and the request as the
//! reason (Claude Code then goes on and does it; tested 2026-11-15); never
//! when `stop_hook_active` is true, so a session cannot be held twice.
//! The owner's "Consolidate Memory Now" pastes `asked_prefix` into the
//! session; that prompt gets the request next to it (UserPromptSubmit).
//! Without CADEX_MEMORY_CONSOLIDATE_AT (memory.consolidateInSession off)
//! nothing here runs.

const std = @import("std");
const files = @import("../../shared/fs.zig");
const c = std.c;

/// What "Consolidate Memory Now" pastes (memory.consolidate-now).
pub const asked_prefix = "Consolidate this session into the project memory";

pub const Reason = enum { context, ready, asked };

pub fn name(reason: Reason) []const u8 {
    return @tagName(reason);
}

/// The context's percent used, from the statusline's `context_window`:
/// `used_percentage` when Claude Code gives it, else the current usage over
/// the window size.
pub fn usedPercent(session_json: []const u8, gpa: std.mem.Allocator) ?f64 {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, session_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const window = parsed.value.object.get("context_window") orelse return null;
    if (window != .object) return null;
    if (number(window.object.get("used_percentage"))) |p| return p;
    const size = number(window.object.get("context_window_size")) orelse return null;
    const usage = window.object.get("current_usage") orelse return null;
    if (usage != .object or size <= 0) return null;
    var used: f64 = 0;
    for ([_][]const u8{ "input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens" }) |key| {
        used += number(usage.object.get(key)) orelse 0;
    }
    return used * 100 / size;
}

fn number(value: ?std.json.Value) ?f64 {
    const v = value orelse return null;
    return switch (v) {
        .integer => |i| @floatFromInt(i),
        .float => |f| f,
        else => null,
    };
}

/// The paths this module reads and writes, for one session.
pub const Paths = struct {
    buf_mark: [1024]u8 = undefined,
    buf_ready: [1024]u8 = undefined,
    buf_usage: [1024]u8 = undefined,
    mark: []const u8 = "",
    ready: []const u8 = "",
    usage: []const u8 = "",

    pub fn init(self: *Paths, data_dir: []const u8, usage_dir: []const u8, session_id: []const u8) bool {
        for (session_id) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_')) return false;
        self.mark = std.fmt.bufPrint(&self.buf_mark, "{s}/consolidate/{s}", .{ data_dir, session_id }) catch return false;
        self.ready = std.fmt.bufPrint(&self.buf_ready, "{s}/consolidate/requests/{s}.ready", .{ data_dir, session_id }) catch return false;
        self.usage = std.fmt.bufPrint(&self.buf_usage, "{s}/sessions/{s}.json", .{ usage_dir, session_id }) catch return false;
        return true;
    }
};

/// The milestone a Stop reached, if any, marked as done so it never comes
/// again for this session.
pub fn atStop(gpa: std.mem.Allocator, paths: *const Paths, threshold: f64, stop_hook_active: bool) ?Reason {
    if (stop_hook_active) return null;
    const done = readSmall(gpa, paths.mark, 4096) catch null;
    defer if (done) |d| gpa.free(d);
    const has = struct {
        fn f(d: ?[]const u8, what: []const u8) bool {
            const text = d orelse return false;
            var lines = std.mem.splitScalar(u8, text, '\n');
            while (lines.next()) |line| if (std.mem.eql(u8, line, what)) return true;
            return false;
        }
    }.f;
    const reason: Reason = blk: {
        if (files.exists(paths.ready) and !has(done, "ready")) break :blk .ready;
        if (!has(done, "context")) {
            const session = readSmall(gpa, paths.usage, 64 * 1024) catch null;
            defer if (session) |s| gpa.free(s);
            if (session) |s| if (usedPercent(s, gpa)) |p| if (p >= threshold) break :blk .context;
        }
        return null;
    };
    if (reason == .ready) remove(paths.ready);
    var line_buf: [16]u8 = undefined;
    const line = std.fmt.bufPrint(&line_buf, "{s}\n", .{name(reason)}) catch return null;
    appendCreating(paths.mark, line) catch return null;
    return reason;
}

/// Whether a prompt is the owner's "Consolidate Memory Now".
pub fn isAsked(prompt: []const u8) bool {
    return std.mem.startsWith(u8, std.mem.trimStart(u8, prompt, " \t\r\n"), asked_prefix);
}

/// The Stop hook's answer that holds the session for the request.
pub fn blockOutput(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    return std.fmt.allocPrint(gpa, "{{\"decision\":\"block\",\"reason\":{f}}}\n", .{std.json.fmt(text, .{})});
}

// Small file helpers (libc, as spool.zig): read a capped file, append a
// line, remove; folders made 0700 like the memory's.

fn zpath(buf: *[1024]u8, path: []const u8) ?[:0]const u8 {
    return std.fmt.bufPrintZ(buf, "{s}", .{path}) catch null;
}

fn readSmall(gpa: std.mem.Allocator, path: []const u8, cap: usize) !?[]u8 {
    var buf: [1024]u8 = undefined;
    const z = zpath(&buf, path) orelse return null;
    const fd = c.open(z.ptr, .{ .ACCMODE = .RDONLY });
    if (fd < 0) return null;
    defer _ = c.close(fd);
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);
    var chunk: [4096]u8 = undefined;
    while (out.items.len < cap) {
        const n = c.read(fd, &chunk, chunk.len);
        if (n <= 0) break;
        try out.appendSlice(gpa, chunk[0..@intCast(n)]);
    }
    return try out.toOwnedSlice(gpa);
}

fn remove(path: []const u8) void {
    var buf: [1024]u8 = undefined;
    const z = zpath(&buf, path) orelse return;
    _ = c.unlink(z.ptr);
}

fn makeParents(path: []const u8) void {
    var buf: [1024]u8 = undefined;
    var i: usize = 1;
    while (std.mem.indexOfScalarPos(u8, path, i, '/')) |slash| : (i = slash + 1) {
        const z = zpath(&buf, path[0..slash]) orelse return;
        _ = c.mkdir(z.ptr, 0o700);
    }
}

fn openFor(path: []const u8, append: bool) !c.fd_t {
    makeParents(path);
    var buf: [1024]u8 = undefined;
    const z = zpath(&buf, path) orelse return error.NameTooLong;
    const fd = c.open(z.ptr, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = append, .TRUNC = !append }, @as(c.mode_t, 0o600));
    return if (fd < 0) error.OpenFailed else fd;
}

fn appendCreating(path: []const u8, data: []const u8) !void {
    const fd = try openFor(path, true);
    defer _ = c.close(fd);
    if (c.write(fd, data.ptr, data.len) != @as(isize, @intCast(data.len))) return error.WriteFailed;
}

fn writeCreating(path: []const u8, data: []const u8) !void {
    const fd = try openFor(path, false);
    defer _ = c.close(fd);
    if (c.write(fd, data.ptr, data.len) != @as(isize, @intCast(data.len))) return error.WriteFailed;
}

const testing = std.testing;

test "the context's percent, given or worked out" {
    try testing.expectEqual(@as(?f64, 72), usedPercent("{\"context_window\":{\"used_percentage\":72}}", testing.allocator));
    const worked = usedPercent("{\"context_window\":{\"context_window_size\":200000,\"current_usage\":{\"input_tokens\":100000,\"cache_read_input_tokens\":40000}}}", testing.allocator).?;
    try testing.expectApproxEqAbs(@as(f64, 70), worked, 0.001);
    try testing.expect(usedPercent("{\"context_window\":null}", testing.allocator) == null);
    try testing.expect(usedPercent("nope", testing.allocator) == null);
}

test "each milestone once, never while stop_hook_active, ready before context" {
    var tmp = try @import("../../shared/test_dir.zig").TestDir.init();
    defer tmp.deinit();
    var dir_buf: [1024]u8 = undefined;
    const data = try std.fmt.bufPrint(&dir_buf, "{s}/memory", .{tmp.path()});
    var usage_buf: [1024]u8 = undefined;
    const usage = try std.fmt.bufPrint(&usage_buf, "{s}/usage", .{tmp.path()});
    var paths: Paths = .{};
    try testing.expect(paths.init(data, usage, "s-1"));
    var bad: Paths = .{};
    try testing.expect(!bad.init(data, usage, "../x"));
    try testing.expect(atStop(testing.allocator, &paths, 70, false) == null);
    try writeCreating(paths.usage, "{\"context_window\":{\"used_percentage\":75}}");
    try writeCreating(paths.ready, "");
    try testing.expect(atStop(testing.allocator, &paths, 70, true) == null);
    try testing.expectEqual(Reason.ready, atStop(testing.allocator, &paths, 70, false).?);
    try testing.expect(!files.exists(paths.ready));
    try testing.expectEqual(Reason.context, atStop(testing.allocator, &paths, 70, false).?);
    try testing.expect(atStop(testing.allocator, &paths, 70, false) == null);
    try testing.expect(isAsked("  Consolidate this session into the project memory."));
    try testing.expect(!isAsked("please consolidate"));
    const out = try blockOutput(testing.allocator, "do \"it\"");
    defer testing.allocator.free(out);
    try testing.expectEqualStrings("{\"decision\":\"block\",\"reason\":\"do \\\"it\\\"\"}\n", out);
}
