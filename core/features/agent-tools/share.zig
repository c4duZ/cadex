//! `cadex share [file]` (plan 39 E, docs/plans/39-terminals-from-the-phone.md):
//! the file's link on the owner's tailnet, for an hour, that the phone's
//! Safari opens (an HTML page working, a picture, a PDF, Word, Markdown
//! rendered) and saves; with no file, the links still valid. The app serves
//! it (`{"v":1,"share":…}`, only local: any process of this user may share
//! the user's files, which it can read anyway).

const std = @import("std");
const hook = @import("hook.zig");

extern "c" fn realpath(path: [*:0]const u8, resolved: [*]u8) ?[*:0]u8;

/// 0 shared or listed, 1 refused or no app (the reason on stderr), 2 usage.
pub fn main(words: []const []const u8) u8 {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    if (words.len > 1) return say(2, "usage: cadex share [file]\n");
    const line = (if (words.len == 1) request(arena, words[0]) else arena.dupe(u8, "{\"v\":1,\"shares\":true}\n")) catch
        return say(1, "cadex: no such file\n");
    var path_buf: [256]u8 = undefined;
    const path = hook.socketPath(&path_buf) orelse return say(1, "cadex: no HOME\n");
    const answer = (hook.exchange(arena, path, line, 10_000) catch null) orelse return say(1, "cadex: Cadex is not open\n");
    const out = render(arena, answer) catch return say(1, "cadex: Cadex's answer did not read\n");
    write(if (out.ok) 1 else 2, out.text);
    return if (out.ok) 0 else 1;
}

/// The request for `file`, by its absolute path (the app runs elsewhere).
pub fn request(arena: std.mem.Allocator, file: []const u8) ![]u8 {
    const z = try arena.dupeZ(u8, file);
    var buf: [1024]u8 = undefined;
    const resolved = realpath(z.ptr, &buf) orelse return error.NoFile;
    return std.fmt.allocPrint(arena, "{{\"v\":1,\"share\":{f}}}\n", .{std.json.fmt(std.mem.span(resolved), .{})});
}

const Out = struct { ok: bool, text: []const u8 };

/// What to print: the link, the list, or the app's reason.
pub fn render(arena: std.mem.Allocator, answer: []const u8) !Out {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, answer, .{});
    if (v != .object) return error.Protocol;
    const ok = if (v.object.get("ok")) |x| x == .bool and x.bool else false;
    if (!ok) {
        const e = str(v, "error");
        return .{ .ok = false, .text = try std.fmt.allocPrint(arena, "cadex: {s}\n", .{if (e.len > 0) e else "refused"}) };
    }
    if (v.object.get("shares")) |list| {
        if (list != .array or list.array.items.len == 0) return .{ .ok = true, .text = "Nothing shared now.\n" };
        var out: std.ArrayList(u8) = .empty;
        for (list.array.items) |item| {
            if (item != .object) continue;
            const minutes = if (item.object.get("minutes")) |m| (if (m == .integer) m.integer else 0) else 0;
            try out.print(arena, "{s}  ({d} min left)\n  {s}\n", .{ str(item, "name"), minutes, str(item, "url") });
        }
        return .{ .ok = true, .text = out.items };
    }
    return .{ .ok = true, .text = try std.fmt.allocPrint(arena, "{s}\n  Open it on your phone (your tailnet only, for an hour).\n", .{str(v, "url")}) };
}

fn str(v: std.json.Value, key: []const u8) []const u8 {
    const x = v.object.get(key) orelse return "";
    return if (x == .string) x.string else "";
}

fn write(fd: c_int, text: []const u8) void {
    @import("../terminal/remote.zig").writeAll(fd, text) catch {};
}

fn say(code: u8, text: []const u8) u8 {
    write(2, text);
    return code;
}

test "the request by absolute path, the link, the list and the reason" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const line = try request(arena, "/tmp/../tmp");
    try t.expect(std.mem.indexOf(u8, line, "\"share\":\"/private/tmp\"") != null);
    try t.expectError(error.NoFile, request(arena, "/no/such/file"));
    const link = try render(arena, "{\"ok\":true,\"url\":\"http://100.64.0.1:47101/s/ab/\",\"name\":\"x.html\"}");
    try t.expect(link.ok and std.mem.startsWith(u8, link.text, "http://100.64.0.1:47101/s/ab/\n"));
    const list = try render(arena, "{\"ok\":true,\"shares\":[{\"url\":\"http://h/s/1/\",\"name\":\"a.pdf\",\"minutes\":42}]}");
    try t.expectEqualStrings("a.pdf  (42 min left)\n  http://h/s/1/\n", list.text);
    const none = try render(arena, "{\"ok\":true,\"shares\":[]}");
    try t.expectEqualStrings("Nothing shared now.\n", none.text);
    const refused = try render(arena, "{\"ok\":false,\"error\":\"this Mac is not on a tailnet\"}");
    try t.expect(!refused.ok and std.mem.eql(u8, refused.text, "cadex: this Mac is not on a tailnet\n"));
}
