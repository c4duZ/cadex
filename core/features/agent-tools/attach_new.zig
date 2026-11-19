//! `cadex new <project> [claude]` (plan 39 C, docs/plans/39-terminals-from-the-phone.md):
//! from the phone, a new tab in a project of Cadex on the Mac (the app runs
//! project.new-terminal or project.new-claude, as a click: the kit, the
//! project's account and memory as for a typed `claude`), then into it as
//! `cadex attach` does. With the app closed, it opens Cadex and waits.

const std = @import("std");
const hook = @import("hook.zig");
const remote = @import("../terminal/remote.zig");
const attach = @import("attach.zig");
const automations = @import("automations.zig");

extern "c" fn _NSGetExecutablePath(buf: [*]u8, size: *u32) c_int;

/// 0 left or the program ended, 1 refused or nothing opened, 2 usage.
pub fn main(words: []const []const u8) u8 {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const claude = words.len == 2 and std.mem.eql(u8, words[1], "claude");
    if (words.len == 0 or words.len > 2 or (words.len == 2 and !claude)) return attach.say(2, "usage: cadex new <project> [claude]\n");
    const line = request(arena, words[0], claude) catch return attach.say(1, "cadex: out of memory\n");
    const answer = ask(arena, line) orelse return attach.say(1, "cadex: Cadex did not answer (could not open it)\n");
    const opened = parseOpened(arena, answer) catch return attach.say(1, "cadex: Cadex's answer did not read\n");
    if (opened.err.len > 0) {
        _ = attach.say(1, "cadex: ");
        _ = attach.say(1, opened.err);
        return attach.say(1, "\n");
    }
    var path_buf: [256]u8 = undefined;
    const path = remote.socketPath(&path_buf) orelse return attach.say(1, "cadex: no HOME\n");
    var conn = remote.Connection.connect(arena, path) catch return attach.say(1, "cadex: the terminal daemon did not answer\n");
    defer conn.deinit(arena);
    if (conn.revision < 2) return attach.say(1, "cadex: opened in Cadex; its terminal daemon is from an older version and shares once it restarts\n");
    return attach.join(arena, &conn, opened.choice);
}

/// `{"v":1,"new":true,"project":…,"claude":…}`.
pub fn request(arena: std.mem.Allocator, project: []const u8, claude: bool) ![]u8 {
    return std.fmt.allocPrint(arena, "{{\"v\":1,\"new\":true,\"project\":{f},\"claude\":{}}}\n", .{ std.json.fmt(project, .{}), claude });
}

/// The app's answer; with no app, Cadex opened in the background and asked
/// again while it starts (up to 30 s: a cold start restores its projects).
fn ask(arena: std.mem.Allocator, line: []const u8) ?[]u8 {
    var path_buf: [256]u8 = undefined;
    const path = hook.socketPath(&path_buf) orelse return null;
    if (hook.exchange(arena, path, line, 10_000) catch null) |answer| return answer;
    if (!openApp(arena)) return null;
    var waited: u32 = 0;
    while (waited < 30_000) : (waited += 500) {
        @import("../../shared/clock.zig").sleepMs(500);
        if (hook.exchange(arena, path, line, 10_000) catch null) |answer| return answer;
    }
    return null;
}

/// CADEX_APP_BUNDLE, else the .app this `cadex` lives in (Contents/Helpers).
fn openApp(arena: std.mem.Allocator) bool {
    if (std.c.getenv("CADEX_APP_BUNDLE")) |bundle| return automations.launch(arena, &.{ "/usr/bin/open", "-g", std.mem.span(bundle) }, false) == 0;
    var buf: [1024]u8 = undefined;
    var size: u32 = buf.len;
    if (_NSGetExecutablePath(&buf, &size) != 0) return false;
    const self_path = std.mem.sliceTo(&buf, 0);
    const bundle = bundleOf(self_path) orelse return false;
    return automations.launch(arena, &.{ "/usr/bin/open", "-g", bundle }, false) == 0;
}

/// "/Applications/Cadex.app" from "/Applications/Cadex.app/Contents/Helpers/cadex".
pub fn bundleOf(path: []const u8) ?[]const u8 {
    const at = std.mem.indexOf(u8, path, ".app/Contents/") orelse return null;
    return path[0 .. at + 4];
}

const Opened = struct { choice: attach.Choice = .{ .id = "", .project = "", .tab = "" }, err: []const u8 = "" };

pub fn parseOpened(arena: std.mem.Allocator, answer: []const u8) !Opened {
    const v = try std.json.parseFromSliceLeaky(std.json.Value, arena, answer, .{});
    if (v != .object) return error.Protocol;
    const ok = v.object.get("ok");
    const field = struct {
        fn get(o: std.json.Value, key: []const u8) []const u8 {
            const x = o.object.get(key) orelse return "";
            return if (x == .string) x.string else "";
        }
    }.get;
    if (ok == null or ok.? != .bool or !ok.?.bool) {
        const e = field(v, "error");
        return .{ .err = if (e.len > 0) e else "refused" };
    }
    const id = field(v, "id");
    if (id.len == 0) return error.Protocol;
    return .{ .choice = .{ .id = id, .project = field(v, "project"), .tab = field(v, "tab") } };
}

test "the request, the answer and the bundle" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    try t.expectEqualStrings("{\"v\":1,\"new\":true,\"project\":\"bkdg \\\"x\\\"\",\"claude\":true}\n", try request(arena, "bkdg \"x\"", true));
    const opened = try parseOpened(arena, "{\"ok\":true,\"id\":\"c1-9\",\"project\":\"cadex\",\"tab\":\"claude\"}");
    try t.expectEqualStrings("c1-9", opened.choice.id);
    try t.expectEqualStrings("cadex", opened.choice.project);
    const refused = try parseOpened(arena, "{\"ok\":false,\"error\":\"no project x; open: cadex\"}");
    try t.expectEqualStrings("no project x; open: cadex", refused.err);
    try t.expectEqualStrings("/Applications/Cadex.app", bundleOf("/Applications/Cadex.app/Contents/Helpers/cadex").?);
    try t.expect(bundleOf("/usr/local/bin/cadex") == null);
}
