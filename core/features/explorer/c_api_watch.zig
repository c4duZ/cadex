//! The explorer's file watching in the C API (include/cadex.h).

const std = @import("std");
const status = @import("../../status.zig");
const workspace = @import("../workspace/workspace.zig");
const watch = @import("watch.zig");

const Watcher = watch.Watcher;

/// Watches `path` and everything below it. on_change runs on the watcher's
/// queue with each batch of changed folders. Stop with
/// cadex_explorer_watch_stop.
pub export fn cadex_explorer_watch(path: ?[*:0]const u8, context: ?*anyopaque, on_change: ?watch.Callback, out: ?*?*Watcher) callconv(.c) status.Code {
    const result = out orelse return status.invalid_argument;
    result.* = null;
    const p = std.mem.span(path orelse return status.invalid_argument);
    const callback = on_change orelse return status.invalid_argument;
    result.* = Watcher.start(std.heap.c_allocator, workspace.registry(), p, callback, context, watch.default_latency_s) catch |err|
        return status.fromError(err);
    return status.ok;
}

/// Stops and frees the watcher; no callback runs after this returns. Must
/// not be called from inside on_change. NULL is accepted.
pub export fn cadex_explorer_watch_stop(watcher: ?*Watcher) callconv(.c) void {
    if (watcher) |w| w.stop();
}

test "watching through the C API refuses outside and stops cleanly" {
    const Noop = struct {
        fn onChange(_: ?*anyopaque, _: [*]const watch.Change, _: usize) callconv(.c) void {}
    };
    var dir = try @import("../../shared/test_dir.zig").TestDir.init();
    defer dir.deinit();
    try dir.makeDir("watched");
    var watcher: ?*Watcher = null;
    try std.testing.expectEqual(status.not_authorized, cadex_explorer_watch(try dir.join("watched"), null, Noop.onChange, &watcher));
    try std.testing.expect(watcher == null);
    _ = try workspace.registry().authorize(try dir.join("watched"));
    try std.testing.expectEqual(status.ok, cadex_explorer_watch(try dir.join("watched"), null, Noop.onChange, &watcher));
    cadex_explorer_watch_stop(watcher);
}
