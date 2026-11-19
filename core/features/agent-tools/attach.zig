//! `cadex attach [n|id]` (plan 39 B, docs/plans/39-terminals-from-the-phone.md):
//! from a terminal that is not a Cadex tab (the owner's phone over SSH),
//! the terminals open in Cadex, by project, and into one of them as a
//! second screen: the Mac keeps showing it, both type. The names come from
//! the app (`{"v":1,"terminals":true}`, no token: the same user, as the
//! automations' `due`); the sessions from the terminal daemon.

const std = @import("std");
const c = std.c;
const hook = @import("hook.zig");
const remote = @import("../terminal/remote.zig");
const session = @import("attach_session.zig");
const menu = @import("attach_menu.zig");

pub const terminals_line = "{\"v\":1,\"terminals\":true}\n";

/// A terminal to join: the daemon's id and how the owner knows it.
pub const Choice = struct { id: []const u8, project: []const u8, tab: []const u8, agent: []const u8 = "" };

/// What the app says: its terminals and its projects, in its order.
pub const App = struct { terminals: []const Choice = &.{}, projects: []const []const u8 = &.{} };

/// 0 left or the program ended, 1 nothing to join (the reason on stderr), 2 usage.
/// With no word, the menu of `cadex` alone (plan 39 D).
pub fn main(words: []const []const u8) u8 {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    if (words.len > 1) return say(2, "usage: cadex attach [number|id]\n");
    var path_buf: [256]u8 = undefined;
    const path = remote.socketPath(&path_buf) orelse return say(1, "cadex: no HOME\n");
    var conn = remote.Connection.connect(arena, path) catch
        return say(1, "cadex: Cadex keeps no terminals here (is Cadex open, with Terminal > Keep sessions on?)\n");
    defer conn.deinit(arena);
    if (conn.revision < 2) return say(1, "cadex: Cadex's terminal daemon is from an older version; it shares terminals once it restarts\n");
    const listed = remote.list(arena, arena, &conn) catch return say(1, "cadex: the terminal daemon did not answer\n");
    const app = appTerminals(arena);
    const choices = merge(arena, listed, app.terminals) catch return say(1, "cadex: out of memory\n");
    if (words.len == 0) return menu.run(arena, &conn, choices, app.projects);
    const choice = pick(choices, words[0]) orelse return say(1, "cadex: no such terminal\n");
    return join(arena, &conn, choice);
}

pub fn join(arena: std.mem.Allocator, conn: *remote.Connection, choice: Choice) u8 {
    _ = conn.join(arena, choice.id) catch return say(1, "cadex: that terminal is gone\n");
    // A clean screen for the replay; the program draws itself again on the size.
    remote.writeAll(1, "\x1b[H\x1b[2J") catch {};
    var code: i32 = 0;
    const end = session.run(arena, conn, &code);
    const name = if (choice.project.len > 0) choice.project else choice.id;
    var buf: [512]u8 = undefined;
    const said = switch (end) {
        .left => std.fmt.bufPrint(&buf, "Left {s} · {s}; it goes on in Cadex.\n", .{ name, choice.tab }),
        .exited => std.fmt.bufPrint(&buf, "{s} · {s} ended ({d}).\n", .{ name, choice.tab, code }),
        .lost => std.fmt.bufPrint(&buf, "Lost the terminal daemon.\n", .{}),
    } catch "";
    remote.writeAll(1, said) catch {};
    return if (end == .lost) 1 else 0;
}

/// The app's names for the daemon's running sessions, in the app's order;
/// with the app closed (or saying nothing), the daemon's ids alone.
pub fn merge(arena: std.mem.Allocator, listed: []const remote.Listed, named: []const Choice) ![]Choice {
    var out: std.ArrayList(Choice) = .empty;
    for (named) |choice| {
        for (listed) |item| if (item.alive and std.mem.eql(u8, item.id, choice.id)) {
            try out.append(arena, choice);
            break;
        };
    }
    if (named.len == 0) for (listed) |item| if (item.alive) try out.append(arena, .{ .id = item.id, .project = "", .tab = item.id });
    return out.items;
}

/// The app's answer to terminals_line, or none.
fn appTerminals(arena: std.mem.Allocator) App {
    var path_buf: [256]u8 = undefined;
    const path = hook.socketPath(&path_buf) orelse return .{};
    const answer = (hook.exchange(arena, path, terminals_line, 3_000) catch null) orelse return .{};
    return parseTerminals(arena, answer) catch .{};
}

pub fn parseTerminals(arena: std.mem.Allocator, answer: []const u8) !App {
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, answer, .{});
    if (parsed != .object) return .{};
    var out: std.ArrayList(Choice) = .empty;
    if (parsed.object.get("terminals")) |rows| if (rows == .array) for (rows.array.items) |row| {
        if (row != .object) continue;
        const id = text(row, "id");
        if (id.len == 0) continue;
        try out.append(arena, .{ .id = id, .project = text(row, "project"), .tab = text(row, "tab"), .agent = text(row, "agent") });
    };
    var names: std.ArrayList([]const u8) = .empty;
    if (parsed.object.get("projects")) |list| if (list == .array) for (list.array.items) |name| {
        if (name == .string and name.string.len > 0) try names.append(arena, name.string);
    };
    return .{ .terminals = out.items, .projects = names.items };
}

fn text(row: std.json.Value, key: []const u8) []const u8 {
    const v = row.object.get(key) orelse return "";
    return if (v == .string) v.string else "";
}

/// "3" (1-based, as the menu numbers them) or a daemon id.
pub fn pick(choices: []const Choice, word: []const u8) ?Choice {
    if (std.fmt.parseInt(usize, word, 10)) |n| {
        if (n >= 1 and n <= choices.len) return choices[n - 1];
    } else |_| {}
    for (choices) |choice| if (std.mem.eql(u8, choice.id, word)) return choice;
    return null;
}

pub fn say(code: u8, message: []const u8) u8 {
    if (message.len > 0) remote.writeAll(2, message) catch {};
    return code;
}

test "the app's names, in its order, for the daemon's running sessions" {
    const t = std.testing;
    var arena_state = std.heap.ArenaAllocator.init(t.allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    const named = try parseTerminals(arena,
        \\{"ok":true,"terminals":[{"id":"c1-b","project":"cadex","tab":"claude","agent":"working"},
        \\{"id":"c1-a","project":"cadex","tab":"zsh"},{"id":"c1-gone","project":"x","tab":"y"},{"project":"no id"}],
        \\"projects":["cadex","bkdg-center"]}
    );
    try t.expectEqual(@as(usize, 3), named.terminals.len);
    try t.expectEqualStrings("bkdg-center", named.projects[1]);
    const listed = [_]remote.Listed{
        .{ .id = "c1-a", .pid = 1, .alive = true, .exit_code = 0, .attached = true },
        .{ .id = "c1-b", .pid = 2, .alive = true, .exit_code = 0, .attached = true },
        .{ .id = "c1-ended", .pid = 3, .alive = false, .exit_code = 0, .attached = false },
    };
    const choices = try merge(arena, &listed, named.terminals);
    try t.expectEqual(@as(usize, 2), choices.len);
    try t.expectEqualStrings("c1-b", choices[0].id);
    try t.expectEqualStrings("working", choices[0].agent);
    try t.expectEqualStrings("zsh", pick(choices, "2").?.tab);
    try t.expectEqualStrings("claude", pick(choices, "c1-b").?.tab);
    try t.expect(pick(choices, "3") == null and pick(choices, "0") == null);
    // The app closed: the daemon's running ids.
    const bare = try merge(arena, &listed, &.{});
    try t.expectEqual(@as(usize, 2), bare.len);
    try t.expectEqualStrings("c1-a", bare[0].tab);
}
