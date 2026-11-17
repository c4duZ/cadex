//! `cadex automations due` (docs/adr/0034-scheduled-automations.md, plan 24
//! E): the program the automations' LaunchAgent runs at their times. It asks
//! the app, through its socket, to check its agenda (`{"v":1,"due":true}`,
//! no token: it says nothing of what to run); with the app closed, it opens
//! Cadex in the background and leaves: the app checks its agenda when it
//! opens. CADEX_APP_BUNDLE (the .app, opened with `open -g`) or CADEX_APP_BIN
//! (an executable, a test instance's, started with CADEX_BACKGROUND=1 in a
//! session of its own) say what to open; the plist sets them.

const std = @import("std");
const hook = @import("hook.zig");

extern "c" fn setsid() c_int;
extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
extern "c" var environ: [*:null]?[*:0]u8;

pub const line = "{\"v\":1,\"due\":true}\n";

/// 0 when the app answered or was opened, 1 when there is nothing to open.
pub fn due() u8 {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();
    var path_buf: [256]u8 = undefined;
    if (hook.socketPath(&path_buf)) |path| {
        if (hook.exchange(arena, path, line, 5_000) catch null) |_| return 0;
    }
    if (std.c.getenv("CADEX_APP_BUNDLE")) |bundle| return launch(arena, &.{ "/usr/bin/open", "-g", std.mem.span(bundle) }, false);
    if (std.c.getenv("CADEX_APP_BIN")) |bin| return launch(arena, &.{std.mem.span(bin)}, true);
    return 1;
}

/// Starts `argv` in a session of its own (the LaunchAgent's group may be
/// ended when this exits), with this environment and, for the app itself,
/// CADEX_BACKGROUND=1: no window in front, no focus taken.
fn launch(arena: std.mem.Allocator, argv: []const []const u8, background: bool) u8 {
    var args: std.ArrayList(?[*:0]const u8) = .empty;
    for (argv) |word| args.append(arena, (arena.dupeZ(u8, word) catch return 1).ptr) catch return 1;
    args.append(arena, null) catch return 1;
    var env: std.ArrayList(?[*:0]const u8) = .empty;
    var i: usize = 0;
    while (environ[i]) |entry| : (i += 1) env.append(arena, entry) catch return 1;
    if (background) env.append(arena, "CADEX_BACKGROUND=1") catch return 1;
    env.append(arena, null) catch return 1;
    const pid = std.c.fork();
    if (pid < 0) return 1;
    if (pid == 0) {
        _ = setsid();
        _ = execve(args.items[0].?, @ptrCast(args.items.ptr), @ptrCast(env.items.ptr));
        std.c._exit(127);
    }
    return 0;
}

test "the request says only: check your agenda" {
    try std.testing.expectEqualStrings("{\"v\":1,\"due\":true}\n", line);
}
