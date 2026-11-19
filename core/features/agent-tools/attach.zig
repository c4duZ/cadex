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

pub const terminals_line = "{\"v\":1,\"terminals\":true}\n";

/// A terminal to join: the daemon's id and how the owner knows it.
pub const Choice = struct { id: []const u8, project: []const u8, tab: []const u8, agent: []const u8 = "" };

/// 0 left or the program ended, 1 nothing to join (the reason on stderr), 2 usage.
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
    const choices = merge(arena, listed, appTerminals(arena)) catch return say(1, "cadex: out of memory\n");
    if (choices.len == 0) return say(1, "cadex: no terminal open in Cadex\n");
    const picked = if (words.len == 1) pick(choices, words[0]) else ask(choices);
    const choice = picked orelse return say(if (words.len == 1) 1 else 0, if (words.len == 1) "cadex: no such terminal\n" else "");
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
fn appTerminals(arena: std.mem.Allocator) []const Choice {
    var path_buf: [256]u8 = undefined;
    const path = hook.socketPath(&path_buf) orelse return &.{};
    const answer = (hook.exchange(arena, path, terminals_line, 3_000) catch null) orelse return &.{};
    return parseTerminals(arena, answer) catch &.{};
}

pub fn parseTerminals(arena: std.mem.Allocator, answer: []const u8) ![]const Choice {
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, arena, answer, .{});
    if (parsed != .object) return &.{};
    const rows = parsed.object.get("terminals") orelse return &.{};
    if (rows != .array) return &.{};
    var out: std.ArrayList(Choice) = .empty;
    for (rows.array.items) |row| {
        if (row != .object) continue;
        const id = text(row, "id");
        if (id.len == 0) continue;
        try out.append(arena, .{ .id = id, .project = text(row, "project"), .tab = text(row, "tab"), .agent = text(row, "agent") });
    }
    return out.items;
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

/// The numbered menu, one key per choice (made for a phone's keyboard).
fn ask(choices: []const Choice) ?Choice {
    var line: [512]u8 = undefined;
    var last: []const u8 = "";
    for (choices, 1..) |choice, n| {
        if (!std.mem.eql(u8, choice.project, last)) {
            last = choice.project;
            const head = std.fmt.bufPrint(&line, "{s}\n", .{if (choice.project.len > 0) choice.project else "Terminals"}) catch continue;
            remote.writeAll(1, head) catch {};
        }
        const agent = if (choice.agent.len > 0) choice.agent else "";
        const row = std.fmt.bufPrint(&line, "  {d:>2}  {s}{s}{s}\n", .{ n, choice.tab, if (agent.len > 0) "  · " else "", agent }) catch continue;
        remote.writeAll(1, row) catch {};
    }
    remote.writeAll(1, "Number (Enter leaves; inside, Ctrl+\\ then d leaves): ") catch {};
    var buf: [32]u8 = undefined;
    const n = c.read(0, &buf, buf.len);
    if (n <= 0) return null;
    const word = std.mem.trim(u8, buf[0..@intCast(n)], " \r\n\t");
    if (word.len == 0) return null;
    return pick(choices, word);
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
        \\{"id":"c1-a","project":"cadex","tab":"zsh"},{"id":"c1-gone","project":"x","tab":"y"},{"project":"no id"}]}
    );
    try t.expectEqual(@as(usize, 3), named.len);
    const listed = [_]remote.Listed{
        .{ .id = "c1-a", .pid = 1, .alive = true, .exit_code = 0, .attached = true },
        .{ .id = "c1-b", .pid = 2, .alive = true, .exit_code = 0, .attached = true },
        .{ .id = "c1-ended", .pid = 3, .alive = false, .exit_code = 0, .attached = false },
    };
    const choices = try merge(arena, &listed, named);
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
