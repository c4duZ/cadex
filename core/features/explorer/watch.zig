//! Tells the app which folders changed on disk: FSEvents on the Mac
//! (`watch_macos.zig`), ReadDirectoryChangesW on Windows
//! (`watch_windows.zig`). The changes of a short window (latency) come
//! as one batch; each batch reaches the app as one callback with every
//! changed folder once. Same thread rule as the terminal's callbacks
//! (terminal/session.zig): they run on the watcher's own thread, must
//! return quickly, and none runs after stop() returns.

const std = @import("std");
const builtin = @import("builtin");
const sync = @import("../../shared/sync.zig");
const clock = @import("../../shared/clock.zig");
const fs = @import("../../shared/fs.zig");
const workspace = @import("../workspace/workspace.zig");

const impl = if (builtin.os.tag == .windows) @import("watch_windows.zig") else @import("watch_macos.zig");

/// One changed folder. `subtree`: the system lost detail (dropped events,
/// root moved or deleted), so everything below must be read again.
pub const Change = extern struct {
    path: [*:0]const u8,
    subtree: bool,
};

pub const Callback = *const fn (context: ?*anyopaque, changes: [*]const Change, count: usize) callconv(.c) void;

/// How long changes gather before a batch. Short enough that the tree
/// feels live; long enough that `git checkout` arrives as a few batches.
pub const default_latency_s: f64 = 0.1;

/// start(gpa, registry, root, callback, context, latency_s) watches the
/// folder `root` (inside an authorized directory) and everything below;
/// stop() ends it and frees it.
pub const Watcher = impl.Watcher;

const testing = std.testing;
const TestDir = @import("../../shared/test_dir.zig").TestDir;

const Seen = struct {
    mutex: sync.Mutex = .{},
    text: [8192]u8 = undefined,
    len: usize = 0,

    fn record(context: ?*anyopaque, changes: [*]const Change, count: usize) callconv(.c) void {
        const self: *Seen = @ptrCast(@alignCast(context.?));
        self.mutex.lock();
        defer self.mutex.unlock();
        for (changes[0..count]) |change| {
            const p = std.mem.span(change.path);
            if (self.len + p.len + 1 > self.text.len) return;
            @memcpy(self.text[self.len..][0..p.len], p);
            self.text[self.len + p.len] = '\n';
            self.len += p.len + 1;
        }
    }

    fn clear(self: *Seen) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.len = 0;
    }

    /// Polls for ~5 s until `line` was reported.
    fn waitFor(self: *Seen, line: []const u8) !void {
        var attempts: u32 = 0;
        while (attempts < 250) : (attempts += 1) {
            self.mutex.lock();
            const found = std.mem.indexOf(u8, self.text[0..self.len], line) != null;
            self.mutex.unlock();
            if (found) return;
            clock.sleepMs(20);
        }
        return error.ChangeNeverReported;
    }
};

test "reports the folder where a file was created, then removed" {
    var dir = try TestDir.init();
    defer dir.deinit();
    try dir.makeDir("sub");
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    _ = try registry.authorize(dir.path());

    var seen: Seen = .{};
    const watcher = try Watcher.start(testing.allocator, &registry, dir.path(), Seen.record, &seen, 0.05);
    defer watcher.stop();
    // Only what happens after the watch is running is reported.
    clock.sleepMs(200);

    try dir.writeFile("sub/new.txt", "x");
    var line: [1024]u8 = undefined;
    const sub = try std.fmt.bufPrint(&line, "{s}{c}sub\n", .{ dir.path(), fs.sep });
    try seen.waitFor(sub);
    seen.clear();
    try dir.tmp.dir.deleteFile(testing.io, "sub/new.txt");
    try seen.waitFor(sub);
}

test "watching outside the workspace is refused" {
    var dir = try TestDir.init();
    defer dir.deinit();
    var registry = workspace.Registry.init(testing.allocator);
    defer registry.deinit();
    var seen: Seen = .{};
    try testing.expectError(error.Outside, Watcher.start(testing.allocator, &registry, dir.path(), Seen.record, &seen, 0.05));
}

test {
    _ = impl;
}
