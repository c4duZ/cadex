//! `cadex` with nothing after it, in a terminal that is not a Cadex tab (the
//! owner's phone over SSH; plan 39 D, docs/plans/39-terminals-from-the-phone.md):
//! the projects and their terminals, numbered, one key per choice, made
//! for a phone's keyboard. A number enters a terminal (`cadex attach`), n
//! opens a terminal in a project and c opens Claude there (`cadex new`).

const std = @import("std");
const c = std.c;
const remote = @import("../terminal/remote.zig");
const attach = @import("attach.zig");
const attach_new = @import("attach_new.zig");

extern "c" fn cfmakeraw(termios_p: *c.termios) void;

pub const Action = union(enum) { enter: usize, new: bool, leave, wait };

/// Keys into a choice among `count` numbered rows: a digit enters at once
/// unless a second digit could follow (more than 9 rows), then Enter or
/// the second digit; n and c ask for a project; Enter, q or Esc leave.
pub const Keys = struct {
    count: usize,
    first: ?usize = null,

    pub fn feed(self: *Keys, key: u8) Action {
        if (std.ascii.isDigit(key)) {
            const d: usize = key - '0';
            if (self.first) |f| {
                self.first = null;
                const n = f * 10 + d;
                return if (n >= 1 and n <= self.count) .{ .enter = n } else .wait;
            }
            if (d * 10 > self.count) return if (d >= 1 and d <= self.count) .{ .enter = d } else .wait;
            self.first = d;
            return .wait;
        }
        if (key == '\r' or key == '\n') {
            if (self.first) |f| {
                self.first = null;
                return if (f >= 1 and f <= self.count) .{ .enter = f } else .wait;
            }
            return .leave;
        }
        self.first = null;
        return switch (key) {
            'n', 'N' => .{ .new = false },
            'c', 'C' => .{ .new = true },
            'q', 'Q', 0x1b, 0x03, 0x04 => .leave,
            else => .wait,
        };
    }
};

/// The menu over the app's names; 0 when the owner leaves.
pub fn run(arena: std.mem.Allocator, conn: *remote.Connection, choices: []const attach.Choice, projects: []const []const u8) u8 {
    show(choices);
    var keys: Keys = .{ .count = choices.len };
    const action = loop(&keys);
    switch (action) {
        .enter => |n| return attach.join(arena, conn, choices[n - 1]),
        .new => |claude| {
            const project = chooseProject(projects) orelse return 0;
            return attach_new.open(arena, project, claude);
        },
        else => return 0,
    }
}

fn show(choices: []const attach.Choice) void {
    var line: [512]u8 = undefined;
    var last: ?[]const u8 = null;
    for (choices, 1..) |choice, n| {
        if (last == null or !std.mem.eql(u8, choice.project, last.?)) {
            last = choice.project;
            const head = std.fmt.bufPrint(&line, "{s}\n", .{if (choice.project.len > 0) choice.project else "Terminals"}) catch continue;
            remote.writeAll(1, head) catch {};
        }
        const row = std.fmt.bufPrint(&line, "  {d:>2}  {s}{s}{s}\n", .{ n, choice.tab, if (choice.agent.len > 0) "  · " else "", choice.agent }) catch continue;
        remote.writeAll(1, row) catch {};
    }
    if (choices.len == 0) remote.writeAll(1, "No terminal open in Cadex.\n") catch {};
    remote.writeAll(1, if (choices.len > 0) "\nnumber enters · n terminal · c Claude · Enter leaves\n" else "\nn terminal · c Claude · Enter leaves\n") catch {};
}

/// Keys until a choice; inside, Ctrl+\ then d leaves (said on the menu of `cadex attach`).
fn loop(keys: *Keys) Action {
    var saved: c.termios = undefined;
    const raw = c.tcgetattr(0, &saved) == 0;
    if (raw) {
        var t = saved;
        cfmakeraw(&t);
        _ = c.tcsetattr(0, .NOW, &t);
    }
    defer if (raw) {
        _ = c.tcsetattr(0, .NOW, &saved);
    };
    while (true) {
        var b: [1]u8 = undefined;
        const n = c.read(0, &b, 1);
        if (n <= 0) return .leave;
        const action = keys.feed(b[0]);
        if (action != .wait) return action;
    }
}

/// The project for n or c: the only one, else a number among them.
fn chooseProject(projects: []const []const u8) ?[]const u8 {
    if (projects.len == 0) {
        remote.writeAll(2, "cadex: no project open in Cadex\n") catch {};
        return null;
    }
    if (projects.len == 1) return projects[0];
    var line: [256]u8 = undefined;
    remote.writeAll(1, "\nIn which project?\n") catch {};
    for (projects, 1..) |name, n| {
        const row = std.fmt.bufPrint(&line, "  {d:>2}  {s}\n", .{ n, name }) catch continue;
        remote.writeAll(1, row) catch {};
    }
    var keys: Keys = .{ .count = projects.len };
    return switch (loop(&keys)) {
        .enter => |n| projects[n - 1],
        else => null,
    };
}

test "one key per choice; two digits past nine; n, c and leaving" {
    const t = std.testing;
    var few: Keys = .{ .count = 4 };
    try t.expectEqual(Action{ .enter = 3 }, few.feed('3'));
    try t.expectEqual(Action.wait, few.feed('7'));
    try t.expectEqual(Action{ .new = true }, few.feed('c'));
    try t.expectEqual(Action{ .new = false }, few.feed('n'));
    try t.expectEqual(Action.leave, few.feed('\r'));
    var many: Keys = .{ .count = 12 };
    try t.expectEqual(Action.wait, many.feed('1'));
    try t.expectEqual(Action{ .enter = 12 }, many.feed('2'));
    try t.expectEqual(Action.wait, many.feed('1'));
    try t.expectEqual(Action{ .enter = 1 }, many.feed('\r'));
    try t.expectEqual(Action{ .enter = 5 }, many.feed('5'));
    try t.expectEqual(Action.leave, many.feed('q'));
}
