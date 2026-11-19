//! A second screen on a session (plan 39 A): the app holds a real shell in
//! the daemon and a guest (the phone's `cadex attach`) joins it, both
//! played by `daemon_client.zig`.

const std = @import("std");
const testing = std.testing;
const clock = @import("../../shared/clock.zig");
const client = @import("daemon_client.zig");
const wire = @import("daemon_wire.zig");
const t = @import("daemon_test.zig");

const mac: @import("pty.zig").Size = .{ .cols = 120, .rows = 40 };
const phone: @import("pty.zig").Size = .{ .cols = 50, .rows = 20 };

/// The guests frame saying `count`, within ~5 s (output frames skipped).
fn waitGuests(conn: *client.Connection, count: u8) !void {
    const deadline = clock.monotonicMs() + 5000;
    while (clock.monotonicMs() < deadline) {
        const f = try conn.next(testing.allocator, 100) orelse continue;
        if (f.kind != .guests) continue;
        var r: wire.Reader = .{ .rest = f.payload };
        if (try r.int(u8) == count) return;
    }
    return error.NeverCounted;
}

/// The pty's size as the shell sees it, "rows cols".
fn expectSize(conn: *client.Connection, rows: u16, cols: u16, tag: []const u8) !void {
    var line: [64]u8 = undefined;
    try t.type_(conn, try std.fmt.bufPrint(&line, "echo {s}-$(stty size | tr ' ' x)\n", .{tag}));
    var want: [64]u8 = undefined;
    try t.waitOutput(conn, try std.fmt.bufPrint(&want, "{s}-{d}x{d}", .{ tag, rows, cols }));
}

test "a guest joins the app's session: both see and type, neither takes it" {
    var d: t.Running = .{ .server = undefined };
    try d.start("guest");
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    try testing.expectEqual(wire.revision, app.revision);
    _ = try app.open(testing.allocator, "pane-g", mac, "/tmp", "/bin/sh");
    try t.type_(&app, "echo before-$((6+6))\n");
    try t.waitOutput(&app, "before-12");

    var guest = try client.Connection.connect(testing.allocator, d.path);
    defer guest.deinit(testing.allocator);
    const ready = try guest.join(testing.allocator, "pane-g");
    try testing.expect(ready.alive and guest.master != null);
    // The screen from before, then what the app types, then what it types.
    try t.waitOutput(&guest, "before-12");
    try waitGuests(&app, 1);
    try t.type_(&app, "echo from-mac-$((1+2))\n");
    try t.waitOutput(&guest, "from-mac-3");
    try t.type_(&guest, "echo from-phone-$((2+3))\n");
    try t.waitOutput(&app, "from-phone-5");

    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var probe = try client.Connection.connect(testing.allocator, d.path);
    defer probe.deinit(testing.allocator);
    const listed = try client.list(testing.allocator, arena.allocator(), &probe);
    try testing.expect(listed.len == 1 and listed[0].attached and listed[0].guests == 1);

    // The app comes back (quit and opened again): the guest stays.
    var again = try client.Connection.connect(testing.allocator, d.path);
    defer again.deinit(testing.allocator);
    _ = try again.attach(testing.allocator, "pane-g");
    try waitGuests(&again, 1);
    try t.type_(&again, "echo back-$((3+4))\n");
    try t.waitOutput(&guest, "back-7");

    // The guest's close lets go; the shell goes on with the app.
    try guest.close(testing.allocator);
    try waitGuests(&again, 0);
    try t.type_(&again, "echo still-$((4+5))\n");
    try t.waitOutput(&again, "still-9");
    try again.close(testing.allocator);
    try d.finish(false);
}

test "the pty takes the smallest screen and grows back when the guest leaves" {
    var d: t.Running = .{ .server = undefined };
    try d.start("sizes");
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    _ = try app.open(testing.allocator, "pane-z", mac, "", "/bin/sh");
    try expectSize(&app, 40, 120, "mac");
    {
        var guest = try client.Connection.connect(testing.allocator, d.path);
        defer guest.deinit(testing.allocator);
        _ = try guest.join(testing.allocator, "pane-z");
        try guest.resize(testing.allocator, phone);
        try expectSize(&app, 20, 50, "both");
        // The app's window grows: still the phone's.
        try app.resize(testing.allocator, .{ .cols = 200, .rows = 60 });
        try expectSize(&app, 20, 50, "grown");
    }
    // The guest's connection ended (the phone lost the network).
    try expectSize(&app, 60, 200, "alone");
    try app.close(testing.allocator);
    try d.finish(false);
}

test "a guest hears the end, and a session closed by the app lets it go" {
    var d: t.Running = .{ .server = undefined };
    try d.start("gend");
    var app = try client.Connection.connect(testing.allocator, d.path);
    defer app.deinit(testing.allocator);
    _ = try app.open(testing.allocator, "pane-e", mac, "", "/bin/sh");
    var guest = try client.Connection.connect(testing.allocator, d.path);
    defer guest.deinit(testing.allocator);
    _ = try guest.join(testing.allocator, "pane-e");
    try t.type_(&guest, "exit 6\n");
    try testing.expectEqual(@as(i32, 6), try t.waitExit(&guest));
    try testing.expectEqual(@as(i32, 6), try t.waitExit(&app));
    // An unknown name, and a daemon's session the guest joins twice.
    var other = try client.Connection.connect(testing.allocator, d.path);
    defer other.deinit(testing.allocator);
    try testing.expectError(error.Refused, other.join(testing.allocator, "pane-none"));
    try d.finish(false);
}

const Session = @import("session.zig").Session;

/// The model's text has `needle` within ~5 s.
fn waitText(s: *Session, needle: []const u8) !void {
    var tries: u32 = 0;
    while (tries < 250) : (tries += 1) {
        const text = try s.copyText(testing.allocator);
        defer testing.allocator.free(text);
        if (std.mem.indexOf(u8, text, needle) != null) return;
        clock.sleepMs(20);
    }
    return error.TextNeverAppeared;
}

test "an app's pane resizes through the daemon, and a guest keeps it small" {
    testing.log_level = .err;
    var d: t.Running = .{ .server = undefined };
    try d.start("pane");
    const keep: @import("session_child.zig").Daemon = .{ .socket = d.path, .id = "pane-r", .attach = false };
    const s = try Session.open(testing.allocator, .{ .size = mac, .shell = "/bin/sh", .daemon = keep });
    try s.resize(.{ .cols = 100, .rows = 30 });
    try s.write("echo pane-$(stty size | tr ' ' x)\n");
    try waitText(s, "pane-30x100");
    var guest = try client.Connection.connect(testing.allocator, d.path);
    defer guest.deinit(testing.allocator);
    _ = try guest.join(testing.allocator, "pane-r");
    try guest.resize(testing.allocator, phone);
    // The app hears the guest (its tab's mark).
    var waited: u32 = 0;
    while (s.child.guests() != 1 and waited < 5000) : (waited += 20) clock.sleepMs(20);
    try testing.expectEqual(@as(u8, 1), s.child.guests());
    try s.write("echo small-$(stty size | tr ' ' x)\n");
    try waitText(s, "small-20x50");
    s.close();
    try d.finish(false);
}
