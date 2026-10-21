//! Spawns real shells: these tests cover the pty, the reader thread and the
//! model working together.

const std = @import("std");
const clock = @import("../../shared/clock.zig");
const testing = std.testing;
const Session = @import("session.zig").Session;

/// Real shells send sequences libghostty-vt logs as "unimplemented" (/bin/sh asks
/// for mode 1034). Harmless, but the build runner reports any test stderr as
/// "failed command", so keep test output to errors.
fn quietLogs() void {
    testing.log_level = .err;
}

/// Polls the session text until it contains `needle` or ~5 s pass.
fn waitForText(session: *Session, needle: []const u8) !void {
    var attempts: u32 = 0;
    while (attempts < 250) : (attempts += 1) {
        const text = try session.copyText(testing.allocator);
        defer testing.allocator.free(text);
        if (std.mem.indexOf(u8, text, needle) != null) return;
        clock.sleepMs(20);
    }
    return error.TextNeverAppeared;
}

test "runs a command in a real shell and shows its output" {
    quietLogs();
    const session = try Session.open(testing.allocator, .{
        .size = .{ .cols = 80, .rows = 24 },
        .shell = "/bin/sh",
    });
    defer session.close();

    // Arithmetic, so the match comes from the shell's output and not from
    // the echo of what we typed.
    try session.write("echo cadex-$((40+2))\n");
    try waitForText(session, "cadex-42");
}

test "starts in the requested directory" {
    quietLogs();
    const session = try Session.open(testing.allocator, .{
        .size = .{ .cols = 80, .rows = 24 },
        .shell = "/bin/sh",
        .cwd = "/usr",
    });
    defer session.close();

    try session.write("pwd\n");
    try waitForText(session, "/usr\n");
}

test "reports a foreground program and the shell exit code" {
    quietLogs();
    const Exit = struct {
        var code: std.atomic.Value(i32) = .init(-1);
        fn onExit(_: ?*anyopaque, exit_code: i32) callconv(.c) void {
            code.store(exit_code, .release);
        }
    };
    Exit.code.store(-1, .release);

    const session = try Session.open(testing.allocator, .{
        .size = .{ .cols = 80, .rows = 24 },
        .shell = "/bin/sh",
        .callbacks = .{ .on_exit = &Exit.onExit },
    });
    defer session.close();

    try session.write("sleep 5\n");
    var attempts: u32 = 0;
    while (!session.hasForegroundProcess() and attempts < 250) : (attempts += 1) clock.sleepMs(20);
    try testing.expect(session.hasForegroundProcess());
    try testing.expect(session.foregroundGroup() > 0);

    // Ctrl+C ends sleep; then the shell exits with code 7.
    try session.write("\x03");
    try session.write("exit 7\n");
    attempts = 0;
    while (Exit.code.load(.acquire) < 0 and attempts < 250) : (attempts += 1) clock.sleepMs(20);
    try testing.expectEqual(@as(i32, 7), Exit.code.load(.acquire));
}

test "closing a session with a running program does not hang" {
    quietLogs();
    const session = try Session.open(testing.allocator, .{
        .size = .{ .cols = 80, .rows = 24 },
        .shell = "/bin/sh",
    });
    try session.write("sleep 100\n");
    clock.sleepMs(100);
    session.close();
}

test "closing while a program floods the terminal does not hang" {
    testing.log_level = .err;
    const session = try Session.open(testing.allocator, .{
        .size = .{ .cols = 80, .rows = 24 },
        .shell = "/bin/sh",
    });
    try session.write("yes cadex\n");
    clock.sleepMs(300);

    // Before the fix close() waited forever for the shell to drain its
    // output. Closing the pty first lets it exit within the SIGHUP grace
    // (0.22 s measured); with the old order only the bounded kill wait
    // saved it (1.02 s), which this limit catches.
    const start = monotonicSeconds();
    session.close();
    try testing.expect(monotonicSeconds() - start < 0.6);
}

fn monotonicSeconds() f64 {
    return @as(f64, @floatFromInt(clock.monotonicMs())) / 1000;
}

test "a local server's address in the output is reported once" {
    quietLogs();
    const Seen = struct {
        var count: std.atomic.Value(u32) = .init(0);
        var last: [128]u8 = undefined;
        fn onUrl(_: ?*anyopaque, url: [*:0]const u8) callconv(.c) void {
            const s = std.mem.span(url);
            @memcpy(last[0..s.len], s);
            last[s.len] = 0;
            _ = count.fetchAdd(1, .release);
        }
    };
    const session = try Session.open(testing.allocator, .{
        .size = .{ .cols = 80, .rows = 24 },
        .shell = "/bin/sh",
        .callbacks = .{ .on_local_url = Seen.onUrl },
    });
    defer session.close();
    // Built by the shell, so the echo of the typed command does not match.
    try session.write("p=8000; echo \"Serving on http://0.0.0.0:$p/ now\"; echo \"again 0.0.0.0:$p/\"\n");
    var attempts: u32 = 0;
    while (Seen.count.load(.acquire) == 0 and attempts < 250) : (attempts += 1) clock.sleepMs(20);
    clock.sleepMs(200);
    try testing.expectEqual(@as(u32, 1), Seen.count.load(.acquire));
    try testing.expectEqualStrings("http://localhost:8000/", std.mem.sliceTo(&Seen.last, 0));
}
